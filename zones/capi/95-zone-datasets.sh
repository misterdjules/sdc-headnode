echo "95 configuring capi zone datasets"

app='capi'
# This needs to run after scmgit pkgsrc package has been installed:

# $app-data dataset name will remain the same always:
zfs set mountpoint=/opt/smartdc/$app-data zones/capi/$app-data
# $app-app-ISO_DATE dataset name will change:
STAMP=$(cat /root/$app-app-timestamp)
zfs set mountpoint=/opt/smartdc/$app "zones/capi/$app-app-$STAMP"
# Get git revision:
cd /opt/smartdc/$app-repo
REVISION=$(/opt/local/bin/git rev-parse --verify HEAD)
# Export complete repo into $app:
cd /opt/smartdc/$app-repo

/opt/local/bin/git checkout-index -f -a --prefix=/opt/smartdc/$app/

# Export only config into $app-data:
cd /opt/smartdc/$app-repo
# Create some directories into $app-data
mkdir -p /opt/smartdc/$app-data/log
mkdir -p /opt/smartdc/$app-data/tmp/pids

# Remove and symlink directories:
if [[ ! -n ${KEEP_DATA_DATASET} ]]; then
  mv /opt/smartdc/$app/config /opt/smartdc/$app-data/config
else
  rm -Rf /opt/smartdc/$app/config
fi

rm -Rf /opt/smartdc/$app/log
rm -Rf /opt/smartdc/$app/tmp
rm -Rf /opt/smartdc/$app/config
ln -s /opt/smartdc/$app-data/log /opt/smartdc/$app/log
ln -s /opt/smartdc/$app-data/tmp /opt/smartdc/$app/tmp
ln -s /opt/smartdc/$app-data/config /opt/smartdc/$app/config

# Save REVISION:
if [[ ! -n ${KEEP_DATA_DATASET} ]]; then
  echo "${REVISION}">/opt/smartdc/$app-data/REVISION
fi
echo "${REVISION}">/opt/smartdc/$app/REVISION

# Save VERSION (Updates based on this):
APP_VERSION=$(/opt/local/bin/git describe --tags)
if [[ ! -n ${KEEP_DATA_DATASET} ]]; then
  echo "${APP_VERSION}">/opt/smartdc/$app-data/VERSION
fi
echo "${APP_VERSION}">/opt/smartdc/$app/VERSION

# Cleanup build products:
cd /root/
rm -Rf /opt/smartdc/$app-repo
rm /root/$app-app-timestamp