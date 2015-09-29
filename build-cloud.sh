#!/bin/bash

export ENV=$1

bash <<"EOT"
set -x

function cleanup {
  # Clean up by destroying the environment.
  juju destroy-environment --yes --force $ENV || true

  # Clean up temp files/dirs
  rm -rf $JUJU_REPOSITORY
  rm -rf $testdir
  rm -f $LOG_DEST
  sudo rm -rf $TMP_JUJU_HOME
  sudo rm -rf $TMP
}
trap cleanup EXIT

# Create a new, temporary JUJU_HOME from the real one
export REAL_JUJU_HOME=$HOME/cloud-city
export TMP_JUJU_HOME=$(mktemp -d)
sudo cp -R $REAL_JUJU_HOME/* $TMP_JUJU_HOME
rm -rf $TMP_JUJU_HOME/environments/*

export HERE=$(pwd)
export JUJU_REPOSITORY=$(mktemp -d)
export LOG_DEST=$(mktemp)
export TMP=$(mktemp -d)
export OUTPUT=$TMP/results.json
export JOB_ID=${job_id}
export CONFIG=${config}
export BUNDLE_ARGS=${bundle}
if [ -n "$BUNDLE_ARGS" ]; then
    BUNDLE_ARGS="-b $BUNDLE_ARGS"
fi

juju destroy-environment --yes --force $ENV || true
$HOME/juju-ci-tools/clean_resources.py -v $ENV || true
# 4G mem for bootstrap node...
juju bootstrap --show-log -e $ENV --constraints "mem=4G" || true
# 2G mem for everything else
juju set-constraints mem=2G

export JUJU_VERSION=$(juju status -e $ENV | grep agent-version | head -n1 | tr -s " " | cut -d " " -f 3)
export START=`date -u +"%Y-%m-%dT%H:%M:%SZ"`

mkdir -m 700 ${TMP}/ssh
cp $TMP_JUJU_HOME/staging-juju-rsa ${TMP}/ssh/id_rsa

sudo docker pull jujusolutions/charmbox:latest
sudo docker run --rm \
    -u ubuntu \
    -e "HOME=/home/ubuntu" \
    -e "JUJU_HOME=/home/ubuntu/.juju" \
    -w "/home/ubuntu" \
    -v ${TMP_JUJU_HOME}:/home/ubuntu/.juju \
    -v ${TMP}/.deployer-store-cache:/home/ubuntu/.juju/.deployer-store-cache \
    -v ${JUJU_REPOSITORY}:/home/ubuntu/charm-repo \
    -v ${TMP}:${TMP} \
    -v ${TMP}/ssh:/home/ubuntu/.ssh \
    -t jujusolutions/charmbox:latest \
    sudo bundletester -F -e $ENV -t $url -l DEBUG -v -r json -o $OUTPUT $BUNDLE_ARGS

EXIT_STATUS=$?
export STOP=`date -u +"%Y-%m-%dT%H:%M:%SZ"`

# make sure we can read the output that the container created
sudo chmod 777 $OUTPUT

artifacts=( $(python <<EOF
import json
import sys

result = json.load(open('$OUTPUT'))
out = {
    "tests": result['tests'],
    "revision": result['revision'],
    "url": "$url",
    "build_number": "$BUILD_NUMBER",
    "parent_build_number": "${parent_build}",
    "substrate": "$ENV",
    "started": "$START",
    "finished": "$STOP",
    "juju_version": "$JUJU_VERSION",
    "bundle": "${bundle}",
}
if "$CONFIG":
    out['config'] = "$CONFIG"

with open('$OUTPUT', 'w') as f:
    json.dump(out, f, indent=2)

sys.stdout.write(result['testdir'] + '\t')
sys.stdout.write(result.get('bundle', '') + '\t')
sys.stdout.write('\n')

EOF
) )

testdir=${artifacts[0]}
bundlefile=${artifacts[1]}

# upload results.json
s3cmd -c $TMP_JUJU_HOME/juju-qa.s3cfg put $OUTPUT s3://juju-qa-data/charm-test/${JOB_NAME}-${BUILD_NUMBER}-results.json

# get and upload all-machines.log
bash <<LOGPERMS
timeout 1m juju ssh -e $ENV 0 sudo chmod go+r /var/log/juju/all-machines.log
LOGPERMS
timeout 1m juju scp -e $ENV 0:/var/log/juju/all-machines.log $LOG_DEST
if [ -s $LOG_DEST ]; then
    tail $LOG_DEST
    s3cmd -c $TMP_JUJU_HOME/juju-qa.s3cfg put $LOG_DEST s3://juju-qa-data/charm-test/${JOB_NAME}-${BUILD_NUMBER}-all-machines-log
fi

if [ -n "${bundlefile}" ]; then
    s3cmd -c $TMP_JUJU_HOME/juju-qa.s3cfg put ${bundlefile} s3://juju-qa-data/charm-test/${JOB_NAME}-${BUILD_NUMBER}-bundle
fi

cp $OUTPUT $HERE

exit $EXIT_STATUS
EOT

EXIT_STATUS=$?
set -eux
if [ $EXIT_STATUS == 0 ]; then
  status="PASS"
else
  status="FAIL"
fi
if [ -n "${callback_url-}" ]; then
  curl "$callback_url" --data-urlencode "status=$status" \
                       --data-urlencode "job_id=$JOB_ID" \
                       --data-urlencode "env=$ENV" \
                       --data-urlencode "build_number=$BUILD_NUMBER" \
                       --data-urlencode "result_url=${BUILD_URL}artifact/results.json"
fi

console_output=$(mktemp)
curl -s --output $console_output ${BUILD_URL}consoleText
s3cmd -c $JUJU_HOME/juju-qa.s3cfg put $console_output s3://juju-qa-data/charm-test/${JOB_NAME}-${BUILD_NUMBER}-consoleText
rm -rf $console_output

exit $EXIT_STATUS
