#!/bin/bash
bash <<"EOT"
set -x

export HERE=$(pwd)
export ENV=charm-testing-lxc
export JUJU_HOME=$HOME/cloud-city
export JUJU_REPOSITORY=$(mktemp -d)
export TMP=$(mktemp -d)
export OUTPUT=$TMP/results.json
export JOB_ID=${job_id}
export CONFIG=${config}
export BUNDLE_ARGS=${bundle}
if [ -n "$BUNDLE_ARGS" ]; then
    BUNDLE_ARGS="-b $BUNDLE_ARGS"
fi

juju destroy-environment --yes --force $ENV || true
juju bootstrap -e $ENV --constraints "mem=2G" || true

export JUJU_VERSION=$(juju status -e $ENV | grep agent-version | head -n1 | tr -s " " | cut -d " " -f 3)
export START=`date -u +"%Y-%m-%dT%H:%M:%SZ"`

mkdir -m 700 ${TMP}/ssh
cp /var/lib/jenkins/cloud-city/staging-juju-rsa ${TMP}/ssh/id_rsa

CHARMBOX=tvansteenburgh/charmbox:latest
sudo docker pull $CHARMBOX
sudo docker run --rm --net=host \
    -u ubuntu \
    -e "HOME=/home/ubuntu" \
    -e "JUJU_HOME=/home/ubuntu/.juju" \
    -w "/home/ubuntu" \
    -v ${JUJU_HOME}:/home/ubuntu/.juju \
    -v ${TMP}/.deployer-store-cache:/home/ubuntu/.juju/.deployer-store-cache \
    -v ${JUJU_REPOSITORY}:/home/ubuntu/charm-repo \
    -v ${TMP}:${TMP} \
    -v ${TMP}/ssh:/home/ubuntu/.ssh \
    -t $CHARMBOX \
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
s3cmd -c ~/cloud-city/juju-qa.s3cfg put $OUTPUT s3://juju-qa-data/charm-test/${JOB_NAME}-${BUILD_NUMBER}-results.json

# get and archive log
LOG_SRC=$JUJU_HOME/$ENV/log/all-machines.log
LOG_DEST=$(mktemp)
sudo chmod go+r $LOG_SRC
cp $LOG_SRC $LOG_DEST
if [ -s $LOG_DEST ]; then
    tail $LOG_DEST
    s3cmd -c ~/cloud-city/juju-qa.s3cfg put $LOG_DEST s3://juju-qa-data/charm-test/${JOB_NAME}-${BUILD_NUMBER}-all-machines-log
    rm -f $LOG_DEST
fi

if [ -n "${bundlefile}" ]; then
    s3cmd -c ~/cloud-city/juju-qa.s3cfg put ${bundlefile} s3://juju-qa-data/charm-test/${JOB_NAME}-${BUILD_NUMBER}-bundle
fi

# Clean up by destroying the environment.
juju destroy-environment --yes --force $ENV || true

cp $OUTPUT $HERE
rm -rf $JUJU_REPOSITORY
rm -rf $testdir
sudo rm -rf $TMP

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
s3cmd -c ~/cloud-city/juju-qa.s3cfg put $console_output s3://juju-qa-data/charm-test/${JOB_NAME}-${BUILD_NUMBER}-consoleText
rm -f $console_output

exit $EXIT_STATUS
