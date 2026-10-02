# The disk build: what fails, what is ruled out, and the next experiment

Last updated: 2026-09-21. Written after seven diagnostic rounds, because six of them
were spent on hypotheses the environment disproved in seconds once tested directly.

## The symptom

`gh workflow run build-disk.yml -f platform=amd64` fails in `Build disk images`, in
both matrix legs, with different targets but the same shape:

| Leg | Failure |
|---|---|
| qcow2 | `RuntimeError: mount: /run/osbuild/containers/storage: permission denied. (code: 32)` |
| anaconda-iso | `RuntimeError: mount: /run/osbuild/tree/dev: permission denied.` |

Each ends with `Build process failed: The process '/usr/bin/sudo' failed with exit code 1`.
The qcow2 leg dies inside osbuild's `container-deploy` stage. The ISO leg gets much
further — it downloads the whole F44 package set — then dies mounting `/dev` into the
build tree.

Also present, and **noise**: `fchownat() of /var/log/wtmp failed: Operation not permitted`
and similar, for `/etc/polkit-1/rules.d`, `/run/systemd/netif`, `/var/lib/tpm2-tss`.
They do not decide the outcome.

## What the failing call actually is

From upstream source (`osbuild/util/containers.py`, `containers_storage_source`):

```python
storage_path = "/run/osbuild/containers/storage"
os.makedirs(storage_path, exist_ok=True)
mg.mount(image_filepath, storage_path, permissions=MountPermissions.READ_WRITE)
```

`MountGuard.mount` shells out to util-linux, so the real command is:

```
mount --make-private -o rbind,rw,0755 <source> /run/osbuild/containers/storage
```

The `<source>` is the host storage that osbuild had already bind-mounted **read-only**
as a build input. Cloning a locked read-only mount writable is a documented way to get
`EACCES` out of `mount(2)` — which is exactly the error text.

## Ruled out, with the evidence that ruled it out

Every line here was a real CI run, not a reading of the docs.

| Claim | Evidence | Verdict |
|---|---|---|
| The runner cannot mount / is not really privileged | `diag-runner.yml` round 1: a `--privileged` container gets `MOUNT_OK`, `CHOWN_OK`, `uid_map` is the identity map (so no user namespace), and the capability set includes `cap_sys_admin` — before *and* after a root podman login | runner is fine |
| The storage bind mount itself is broken | round 3: `mount --bind` → `BIND_OK`; round 5: the exact `--make-private -o rbind,rw,0755` → `WHOLE_OK`; round 6: still `POPULATED_WHOLE_OK` with the image pulled and 41 overlay mounts visible | the call works by hand |
| The runner image version | round 4: the same build on `ubuntu-24.04` and `ubuntu-26.04` — same outcome both times | not the runner |
| Our GHCR login / private-image auth | the login step passes and the build proceeds past pull, manifest generation and into osbuild stages | auth is fine |
| `--use-librepo=True` breaks the storage mount | removed it; the failure is unchanged. The one build that has *ever* succeeded had it | wrong diagnosis, flag restored |
| Dropping the host storage volume | the builder refuses outright: `could not access container storage, did you forget -v /var/lib/containers/storage:...?` | the volume is **required** |
| The environment simply cannot build disks | round 7: a public `fedora-bootc` image built end to end, directly, on both runner images | the environment can build |

## What is left

One variable group remains untested: **which of our image, the pre-pull, and the two
flags differs from the build that worked.** Round 7's success had
`--rootfs ext4 --use-librepo=True`, a public image, and a host pre-pull. Our failing
builds had none of the flags and a private image that was pre-pulled.

`.github/workflows/diag-builder.yml` holds that experiment, four legs, one variable
each, ready to dispatch. Read leg D (the public control) first:

- **D fails** → the environment regressed; nothing in the run is about our image.
- **D passes, C fails** → the difference is our image (ublue/Aurora-derived); compare
  its storage/driver metadata next.
- **D and C both pass** → the missing flags were the whole fix; add them to
  `build-disk.yml`.

Run 35649008504 was the first attempt and is **not** usable, for two separate reasons:
the diagnostic workflow did not declare `permissions: packages: read`, so its root podman
login was refused with `invalid username/password: unauthorized` and legs A, B and D died
at `failed to inspect the image: exit status 125` — which reads like a build failure and
is actually bad credentials; and the public control omitted `--rootfs`, so it died with
`missing required info: DefaultRootFs` before reaching anything under test. The corrected
workflow declares the permission and gives fedora-bootc the `--rootfs ext4` it requires.

## The lessons that cost the most

1. **A green job can hide a failed build.** The first fix candidate reported success on
   both legs while the builder exited 1 — the step piped BIB's output through `tail` and
   never propagated the exit code, and every later `ls`/`find` succeeded. Any CI step
   that runs the builder must `set -o pipefail` and `exit` the captured status. Green
   must mean "an image file exists".
2. **Reproduce the operation, don't theorise about it.** "Permission denied" on a mount
   is answerable in thirty seconds: run the mount. Seven rounds here were spent on
   plausible mechanisms that a one-minute test disproved.
3. **One variable per run.** A/B on the runner image, then on the auth, then on the
   storage — designed as a four-way bisect from the start, this would have taken two
   runs instead of seven.
4. `permissions:` on a workflow is easy to forget and produces a *misleading* error:
   a legitimate private image looks like bad credentials.

## The two os-release rules

Separate bug, same workflow, also only visible in the disk build — now guarded by
`tools/check-os-release.sh` and documented in `PROJECT-STATE.md`: no comments in the
file (a `#` line → `readOSRelease: invalid input`) and `ID` must stay `fedora`
(renaming it → `could not find def file for distro primelinux-44`).
