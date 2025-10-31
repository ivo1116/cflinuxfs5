# Cloud Foundry stack: cflinuxfs5

This stack is derived from Ubuntu 24.04 LTS (Noble Numbat)

## Dependencies

* GNU make
* Docker >= 20.10.9

## Creating a rootfs tarball

To create a rootfs for the cflinuxfs5 stack:

```shell
make
```

This will create the `cflinuxfs5.tar.gz` file, which is the artifact used as the rootfs in Cloud Foundry deployments.

# Creating a BOSH release from the rootfs tarball

To start, clone the [repository](https://github.com/cloudfoundry/cflinuxfs5-release) containing the cflinuxfs5-rootfs BOSH release:

```shell
git clone git@github.com:cloudfoundry/cflinuxfs5-release.git
cd cflinuxfs5-release
```

Replace the old cflinuxfs5 tarball with the new tarball created above:

```shell
rm -f config/blobs.yml
mkdir -p blobs/rootfs
cp <path-to-new-tarball>/cflinuxfs5.tar.gz blobs/rootfs/cflinuxfs5-new.tar.gz
```

Create a dev release and upload it to your BOSH deployment:

```shell
bosh create release --force --with-tarball --name cflinuxfs5-rootfs
bosh upload release <generated-dev-release-tar-file>
```

If your Diego deployment manifest has `version: latest` indicated for the `cflinuxfs5` release, then redeploying Diego will enable this new rootfs.

# Release pipeline

The generation and release of a new rootfs happens on the [cflinuxfs5](https://buildpacks.ci.cf-app.com/pipelines/cflinuxfs5) CI pipeline.
