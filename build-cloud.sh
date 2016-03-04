#!/bin/bash

set -x

if [ -n "${callback_url-}" ]; then
  curl "$callback_url" --data-urlencode "status=RUNNING" \
                       --data-urlencode "job_id=$job_id" \
                       --data-urlencode "env=$1" \
                       --data-urlencode "build_number=$BUILD_NUMBER" \
                       --data-urlencode "build_url=$BUILD_URL"
fi

export ENV=$1
export REAL_JUJU_HOME=$HOME/cloud-city

if [ $ENV == "charm-testing-lxc" ]; then
  export LOCAL_LOG=true
  export DOCKER_NET='--net=host'
fi
if [ $ENV == "charm-testing-power8-maas" ]; then
  export DOCKER_DNS='--dns=8.8.8.8 --dns=192.168.64.2'
  export DOCKER_DNS_SEARCH='--dns-search=maas'
fi

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
export TMP_JUJU_HOME=$(mktemp -d)
export JUJU_HOME=$TMP_JUJU_HOME
cp -R $REAL_JUJU_HOME/* $TMP_JUJU_HOME
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

if [ $ENV == "charm-testing-lxc" ] ; then
  if ! juju bootstrap --show-log -e $ENV --constraints "mem=2G" ; then
    export JUJU_HOME=$REAL_JUJU_HOME
    $HOME/.juju-plugins/juju-clean $ENV
    export JUJU_HOME=$TMP_JUJU_HOME
    juju bootstrap --show-log -e $ENV --constraints "mem=2G"
  fi
else
  $HOME/juju-ci-tools/clean_resources.py -v $ENV || true
  juju bootstrap --show-log -e $ENV --constraints "mem=4G" || true
fi

juju set-constraints -e $ENV mem=2G

#if [ $ENV == "charm-testing-power8-maas" ]; then
#  juju set-env http-proxy=91.189.89.33:3128
#  juju set-env https-proxy=91.189.89.33:3128
#  juju set-env apt-http-proxy=91.189.89.33:3128
#  juju set-env apt-https-proxy=91.189.89.33:3128
#  juju set-env apt-ftp-proxy=91.189.89.33:3128
#  juju set-env no-proxy=127.0.0.1,10.245.71.134,192.168.64.2,192.168.64.1,192.168.65.1,192.168.65.2,192.168.65.3,192.168.65.4,192.168.65.5,192.168.65.6,192.168.65.7,192.168.65.8,192.168.65.9,192.168.65.10,192.168.65.11,192.168.65.12,192.168.65.13,192.168.65.14,192.168.65.15,192.168.65.16,192.168.65.17,192.168.65.18,192.168.65.19,192.168.65.20,192.168.65.21,192.168.65.22,192.168.65.23,192.168.65.24,192.168.65.25,192.168.65.26,192.168.65.27,192.168.65.28,192.168.65.29,192.168.65.30,192.168.65.31,192.168.65.32,192.168.65.33,192.168.65.34,192.168.65.35,192.168.65.36,192.168.65.37,192.168.65.38,192.168.65.39,192.168.65.40,192.168.65.41,192.168.65.42,192.168.65.43,192.168.65.44,192.168.65.45,192.168.65.46,192.168.65.47,192.168.65.48,192.168.65.49,192.168.65.50,192.168.65.51,192.168.65.52,192.168.65.53,192.168.65.54,192.168.65.55,192.168.65.56,192.168.65.57,192.168.65.58,192.168.65.59,192.168.65.60,192.168.65.61,192.168.65.62,192.168.65.63,192.168.65.64,192.168.65.65,192.168.65.66,192.168.65.67,192.168.65.68,192.168.65.69,192.168.65.70,192.168.65.71,192.168.65.72,192.168.65.73,192.168.65.74,192.168.65.75,192.168.65.76,192.168.65.77,192.168.65.78,192.168.65.79,192.168.65.80,192.168.65.81,192.168.65.82,192.168.65.83,192.168.65.84,192.168.65.85,192.168.65.86,192.168.65.87,192.168.65.88,192.168.65.89,192.168.65.90,192.168.65.91,192.168.65.92,192.168.65.93,192.168.65.94,192.168.65.95,192.168.65.96,192.168.65.97,192.168.65.98,192.168.65.99,192.168.65.100,192.168.65.101,192.168.65.102,192.168.65.103,192.168.65.104,192.168.65.105,192.168.65.106,192.168.65.107,192.168.65.108,192.168.65.109,192.168.65.110,192.168.65.111,192.168.65.112,192.168.65.113,192.168.65.114,192.168.65.115,192.168.65.116,192.168.65.117,192.168.65.118,192.168.65.119,192.168.65.120,192.168.65.121,192.168.65.122,192.168.65.123,192.168.65.124,192.168.65.125,192.168.65.126,192.168.65.127,192.168.65.128,192.168.65.129,192.168.65.130,192.168.65.131,192.168.65.132,192.168.65.133,192.168.65.134,192.168.65.135,192.168.65.136,192.168.65.137,192.168.65.138,192.168.65.139,192.168.65.140,192.168.65.141,192.168.65.142,192.168.65.143,192.168.65.144,192.168.65.145,192.168.65.146,192.168.65.147,192.168.65.148,192.168.65.149,192.168.65.150,192.168.65.151,192.168.65.152,192.168.65.153,192.168.65.154,192.168.65.155,192.168.65.156,192.168.65.157,192.168.65.158,192.168.65.159,192.168.65.160,192.168.65.161,192.168.65.162,192.168.65.163,192.168.65.164,192.168.65.165,192.168.65.166,192.168.65.167,192.168.65.168,192.168.65.169,192.168.65.170,192.168.65.171,192.168.65.172,192.168.65.173,192.168.65.174,192.168.65.175,192.168.65.176,192.168.65.177,192.168.65.178,192.168.65.179,192.168.65.180,192.168.65.181,192.168.65.182,192.168.65.183,192.168.65.184,192.168.65.185,192.168.65.186,192.168.65.187,192.168.65.188,192.168.65.189,192.168.65.190,192.168.65.191,192.168.65.192,192.168.65.193,192.168.65.194,192.168.65.195,192.168.65.196,192.168.65.197,192.168.65.198,192.168.65.199,192.168.65.200,192.168.65.201,192.168.65.202,192.168.65.203,192.168.65.204,192.168.65.205,192.168.65.206,192.168.65.207,192.168.65.208,192.168.65.209,192.168.65.210,192.168.65.211,192.168.65.212,192.168.65.213,192.168.65.214,192.168.65.215,192.168.65.216,192.168.65.217,192.168.65.218,192.168.65.219,192.168.65.220,192.168.65.221,192.168.65.222,192.168.65.223,192.168.65.224,192.168.65.225,192.168.65.226,192.168.65.227,192.168.65.228,192.168.65.229,192.168.65.230,192.168.65.231,192.168.65.232,192.168.65.233,192.168.65.234,192.168.65.235,192.168.65.236,192.168.65.237,192.168.65.238,192.168.65.239,192.168.65.240,192.168.65.241,192.168.65.242,192.168.65.243,192.168.65.244,192.168.65.245,192.168.65.246,192.168.65.247,192.168.65.248,192.168.65.249,192.168.65.250,192.168.65.251,192.168.65.252,192.168.65.253,192.168.65.254,192.168.65.255
#fi

export JUJU_VERSION=$(juju status -e $ENV | grep agent-version | head -n1 | tr -s " " | cut -d " " -f 3)
export START=`date -u +"%Y-%m-%dT%H:%M:%SZ"`

mkdir -m 700 ${TMP}/ssh
cp $TMP_JUJU_HOME/staging-juju-rsa ${TMP}/ssh/id_rsa

CHARMBOX=jujusolutions/charmbox:latest
sudo docker pull $CHARMBOX
sudo docker run --rm $DOCKER_NET \
  $DOCKER_DNS \
  $DOCKER_DNS_SEARCH \
  -u ubuntu \
  -e "HOME=/home/ubuntu" \
  -e "JUJU_HOME=/home/ubuntu/.juju" \
  -w "/home/ubuntu" \
  -v ${TMP_JUJU_HOME}:/home/ubuntu/.juju \
  -v ${TMP}/.deployer-store-cache:/home/ubuntu/.juju/.deployer-store-cache \
  -v ${JUJU_REPOSITORY}:/home/ubuntu/charm-repo \
  -v ${TMP}:${TMP} \
  -v ${TMP}/ssh:/home/ubuntu/.ssh \
  -t $CHARMBOX \
  sh -c "bzr whoami 'Tim Van Steenburgh <tvansteenburgh@gmail.com>' && sudo bundletester -F -e $ENV -t $url -l DEBUG -v -r json -o $OUTPUT $BUNDLE_ARGS"

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

if [[ $LOCAL_LOG ]] ; then
  # get local all-machines.log
  LOG_SRC=$TMP_JUJU_HOME/$ENV/log/all-machines.log
  LOG_DEST=$(mktemp)
  sudo chmod go+r $LOG_SRC
  cp $LOG_SRC $LOG_DEST
else
  # get remote all-machines.log
bash <<LOGPERMS
timeout 1m juju ssh -e $ENV 0 sudo chmod go+r /var/log/juju/all-machines.log
LOGPERMS
  timeout 1m juju scp -e $ENV 0:/var/log/juju/all-machines.log $LOG_DEST
fi

# upload all-machines.log to S3
if [ -s $LOG_DEST ]; then
    tail $LOG_DEST
    s3cmd -c $TMP_JUJU_HOME/juju-qa.s3cfg put $LOG_DEST s3://juju-qa-data/charm-test/${JOB_NAME}-${BUILD_NUMBER}-all-machines-log
    # save as jenkins build artifact
    cp $LOG_DEST $HERE/all-machines.log
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
                       --data-urlencode "job_id=$job_id" \
                       --data-urlencode "env=$ENV" \
                       --data-urlencode "build_number=$BUILD_NUMBER" \
                       --data-urlencode "build_url=$BUILD_URL" \
                       --data-urlencode "result_url=${BUILD_URL}artifact/results.json"
fi

console_output=$(mktemp)
curl -s --output $console_output ${BUILD_URL}consoleText
s3cmd -c $REAL_JUJU_HOME/juju-qa.s3cfg put $console_output s3://juju-qa-data/charm-test/${JOB_NAME}-${BUILD_NUMBER}-consoleText
rm -rf $console_output

exit $EXIT_STATUS
