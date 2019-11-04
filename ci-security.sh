#!/bin/bash
set -x
# Exit on error
set -e

# Functions
python_tool_install() {
    # Install python3
    sudo apt-get install software-properties-common
    sudo add-apt-repository ppa:deadsnakes/ppa
    sudo apt-get update
    sudo apt-get install python3.6
    python3 --version
    # Install curl
    sudo apt-get update
    sudo apt-get install curl
    sudo apt install python3-pip
    pip install wheel
    pip --version
    export PATH="$PATH:~/.local/bin"
}

dotnet_tool_install() {
    # Register Microsoft key and feed
    wget -q https://packages.microsoft.com/config/ubuntu/18.04/packages-microsoft-prod.deb
    sudo dpkg -i packages-microsoft-prod.deb
    # Install .NET SDK
    sudo add-apt-repository universe
    sudo apt-get install -y apt-transport-https
    sudo apt-get update
    sudo apt-get install dotnet-sdk-3.0
}

node_install() {
    sudo apt-get install curl
    curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash -
    sudo apt-get install nodejs && node -v && npm -v
}

# Set directory to search
DIR=$1
# Check project type: .NET (C# or cs) or python
if [[ -n $(find $DIR -name '*.csproj' -o -name '*.vbproj' -o -name 'packages.config' -o -name '*.sln') ]]; then
    echo "C# project"
    TYPE="C#"
elif [[ -n $(find $DIR -name '*.py') ]]; then
    echo "Python project"
    TYPE="Python"
elif [[ -n $(find $DIR -name 'package.json' -o -name 'yarn.lock') ]]; then
    echo "NodeJS project"
    TYPE="Node"
fi

case $TYPE in
    "C#")
        echo "Hello C#!" ;
        dotnet_tool_install ;
        dotnet --info
        dotnet tool install --tool-path . CycloneDX ;
        #./dotnet-CycloneDX --help
        ./dotnet-CycloneDX $DIR -o $DIR
        cat $DIR/bom.xml
        ;;

    "Python")
        echo "Hello python!" ;
        python_tool_install ;
        pip freeze > requirements.txt
        # Install cyclonedx to create sbom
        pip install cyclonedx-bom ;
        #3. Run it and it will generate sbom in current directory
        pip show cyclonedx-bom ;
        echo $PATH ;
        #cyclonedx-py -i $DIR/requirements.txt -o $DIR ;
        cyclonedx-py
        ls -ltr $DIR
        #ls -ltr /home/vsts/.local/lib/python2.7/site-packages/
        #ls -ltr ~/.local/bin
        cat $DIR/bom.xml
        ;;

    "Node")
        echo "Hello node! Let me setup the env..";
        node_install ;
        sudo npm install -g @cyclonedx/bom ;
        cd $DIR
        npm install ;
        ls -ltr ;
        cyclonedx-bom -o bom.xml ;
        ls -ltr
        cd security-scans
        #cat bom.xml
     ;;

    *)
        echo ":(" ;
        echo "Project type not supported. Only .NET, NodeJS and Python are supported." ;
        exit 1
esac
#exit 0

# Read project UUID from env
DEFAULT_UUID="2d395a41-d684-45c7-a8f9-92d602a43223"
DEFAULT_KEY="mJaqkPN9JFzFwAKGffU1uN6CuW5Uu5dU"
PROJECT_UUID=${PROJECT_UUID:-$DEFAULT_UUID}

API_KEY=${TEAM_KEY:-$DEFAULT_KEY}
# Generate base64 encoded bom without any whitespaces
#b64bom=$(base64 -w 0 $DIR/bom.xml)
mv $DIR/bom.xml .

#echo $b64bom
#5. Post sbom to depenedency track
cat > payload.json <<__HERE__
{
  "project": "${PROJECT_UUID}",
  "bom": "$(cat bom.xml |base64 -w 0 -)"
}
__HERE__

RES="$(curl -X "PUT" "http://104.43.15.124:443/api/v1/bom" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: ${API_KEY}" \
        -d @payload.json)"
#        -F "project=${PROJECT_UUID}" \
#        -F "bom=${b64bom}"

# RES=curl -i -X "POST" "http://104.43.15.124:443/api/v1/bom" \
#         -H "Content-Type:multipart/form-data" \
#         -H "X-API-Key: ${API_KEY}" \
#         -F "project=${PROJECT_UUID}" \
#         -F "bom=${b64bom}"
#echo $RES
# RES="$(curl -X "PUT" "http://104.43.15.124:443/api/v1/bom" \
#          -H 'Content-Type: application/json' \
#          -H "X-API-Key: ${API_KEY}" \
#          -d '{
#                 "project": "'${PROJECT_UUID}'",
#                 "bom": "'${b64bom}'"
#             }')"

TOKEN=$(echo $RES | jq -r '.token')

# Pool DT and pull results when ready
if [[ -z $TOKEN ]]; then
    echo "BOM upload failed. Check error: ${RES}"
else 
    while :
    do
        echo "Dependency Track is scaning,please wait.."
        RESULTS="$(curl -X "GET" "http://104.43.15.124:443/api/v1/bom/token/${TOKEN}" \
                    -H 'Content-Type: application/json' \
                    -H "X-API-Key: ${API_KEY}")"
        processing=$(echo $RESULTS | jq -r '.processing')
        if [[ $processing = false ]]; then
            echo "Scanning..Done!"
            FINDINGS="$(curl -X "GET" "http://104.43.15.124:443/api/v1/finding/project/${PROJECT_UUID}" \
                    -H 'Content-Type: application/json' \
                    -H "X-API-Key: ${API_KEY}")"
            break
        else
            continue
        fi
    done 
fi

echo $FINDINGS




