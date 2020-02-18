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
    sudo apt-get update 
    sudo apt-get install -y apt-transport-https
    sudo apt-get update
    sudo apt-get install -y dotnet-sdk-3.0
}

node_install() {
    sudo apt-get install curl
    curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash -
    sudo apt-get update
    sudo apt-get install nodejs && node -v && npm -v
}


# Show Usage
usage() {
cat << EOF  
Usage: ./ci-security.sh <path-to-project-dir> -s [path-to-sln-file] 
1. For .NET project
    ./ci-security.sh <path-to-project-dir> -s <path-to-sln-file>
    e.g.
    ./ci-security.sh /src -s /src/project.sln

2. For NPM project and Python project
    ./ci-security.sh <path-to-project-dir>
    e.g.
    ./ci-security.sh /src
Options:
-h      Display help

-s      Path to *.sln/*.csproj/project (required only for .NET project). 

EOF
}
#  Dep-Track and Dojo URLs
DT_URL="https://deptrack.australiasoutheast.cloudapp.azure.com/api/v1"
DD_URL="https://52.163.231.2/api/v2"
# Read values from env
# Dep Track API Key and Project UUIDs are unique to Project/team
DEFAULT_PROJECT_UUID="2d395a41-d684-45c7-a8f9-92d602a43223"
DEFAULT_API_KEY="6esBJT96rlTNMfivA09hyikpHPNtV7Rz"
PROJECT_UUID=${PROJECT_UUID:-$DEFAULT_PROJECT_UUID}
# Dojo API key is common
DD_KEY="6f1f60c9bf8161a16227470c09b53298b42ed62e" 
DD_API_KEY="Token ${DD_KEY}"
API_KEY=${API_KEY:-$DEFAULT_API_KEY}

# Check env variables if they are set
if [ -z "$COMMIT_ID" ]; then 
    echo "Commit ID not set in environment. Please set."
    exit 1
fi

if [ -z "$REPO_URL" ]; then 
    echo "Repo URL not set in environment. Please set."
    exit 1
fi
if [ -z "$BRANCH" ]; then 
    echo "Branch not set in environment. Please set."
    exit 1
fi
if [ -z "$BUILD_ID" ]; then 
    echo "Build Id not set in environment. Please set."
    exit 1
fi

if [ -z "$DD_KEY" ]; then 
    echo "Defect dojo API key not set in environment. Please set."
    exit 1
fi

# Set SLN to null
SLN=Null
while getopts "s:" arg; do
    case "${arg}" in
        s)
            SLN=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))
DIR=${1?$( usage )}
echo "DIR = ${DIR}"

if [[ "$SLN" != "Null"  ]]; then
    # Validition for .NET projects
    if [[ ! -z "${SLN}" ]]; then
        echo "Path to SLN file = ${SLN}"
        # It looks like a .net project, check file type
        #filename=$(echo "${SLN##*/}")
        filename=$(basename "$SLN" | sed -r 's|^(.*?)\.\w+$|\1|')
        echo "filename = ${filename}"
        #ext=$(echo "${SLN##*.}")
        ext=$(echo "$SLN" | sed 's/^.*\.//')
        echo "ext = ${ext}"
        if [[ -z $filename || -z $ext ]]; then
            echo "Missing filename or extension, please check .NET project path to sln file."
            exit 1
        fi
        # Check if file exists
        if [[ -n $(find $DIR -type f -name "${filename}.${ext}") ]]; then
            # file exists, lets verify type
            if [[ $ext == "sln" || $ext == "csproj" || $ext == "vbproj" ]]; then
                echo ".NET project"
                TYPE=".NET"
            elif [[ $filename == "projects.config" ]]; then
                echo ".NET project"
                TYPE=".NET"
            else
                echo "Missing filename, .NET project supported filetypes are *.sln, *.csproj, *.vbproj & projects.config"
                exit 1
            fi
        else
            echo "Could not find ${filename}.${ext}, please check filename is correct."
            exit 1
        fi
    else
        echo "Path to sln file is empty"
        exit 1
    fi
else
    # Check project type: NPM and python
    if [[ -n $(find $DIR -maxdepth 1 -type f -name "*.py") ]]; then
        echo "Python project"
        TYPE="Python"
    elif [[ -n $(find $DIR -maxdepth 1 -type f -name "package.json" -o -name "yarn.lock") ]]; then
        echo "NodeJS project"
        TYPE="Node"
    fi
fi

case $TYPE in
    ".NET")
        echo "Hello .NET!" ;
        dotnet_tool_install ;
        dotnet --info
        dotnet tool install --tool-path . CycloneDX ;
        #./dotnet-CycloneDX --help
        #./dotnet-CycloneDX $SLN -o $DIR
        ./dotnet-CycloneDX $SLN -o $DIR
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

# Install jq
if $(dpkg-query -l "jq" | grep -q ^.i ); then
    jq --version
else
    sudo apt-get update -y
    sudo apt-get install -y jq
fi


# Generate base64 encoded bom without any whitespaces
mv $DIR/bom.xml .

#5. Post sbom to depenedency track
cat > payload.json <<__HERE__
{
  "project": "${PROJECT_UUID}",
  "bom": "$(cat bom.xml |base64 -w 0 -)"
}
__HERE__

# New
RES="$(curl -k -X "PUT" "${DT_URL}/bom" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: ${API_KEY}" \
        -d @payload.json)"

#http_status=$(echo $RES | grep "HTTP/1.1" | awk '{print $2}')
#echo $http_status
# if [ ! $http_status -eq '200' ]; then
#     echo "Error ${http_status}: ${RES}"
#     exit 1
# fi


echo $RES
TOKEN=$(echo $RES | jq -r '.token')

# Pool DT and pull results when ready
if [[ -z $TOKEN ]]; then
    echo "BOM upload failed. Check error: ${RES}"
else 
    while :
    do
        echo "Dependency Track is scaning,please wait.."
        RESULTS="$(curl -k -X "GET" "${DT_URL}/bom/token/${TOKEN}" \
                    -H 'Content-Type: application/json' \
                    -H "X-API-Key: ${API_KEY}")"
        processing=$(echo $RESULTS | jq -r '.processing')
        if [[ $processing = false ]]; then
            echo "Scanning..Done!"
              FINDINGS="$(curl -k -X "GET" "${DT_URL}/finding/project/${PROJECT_UUID}" \
                    -H 'Content-Type: application/json' \
                    -H "X-API-Key: ${API_KEY}")"
            break
        else
            continue
        fi
    done 
fi

# Search through findings and report results here
c=0; h=0; m=0; l=0; u=0;
for severity in $(echo $FINDINGS | jq -r '.[].vulnerability.severity')
do
    case $severity in
        "CRITICAL")
            c=$((c+1))
        ;;
        "HIGH")
            h=$((h+1)) 
        ;;
        "MEDIUM")
            m=$((m+1))
        ;;
        "LOW")
            l=$((l+1))
        ;;
        "UNASSIGNED")
            u=$((u+1))
    esac
done


# Export data from Dep Track
json_export="$(curl -k --silent "GET" "${DT_URL}/finding/project/${PROJECT_UUID}/export" \
            -H 'Content-Type: application/json' \
            -H "X-API-Key: ${API_KEY}")"

#echo $json_export
# Grep project name from dep track
DT_PROJECT_NAME=$(echo $json_export | jq '.project.name')
if [ "$DT_PROJECT_NAME" == "" ]; then
	echo "Project does not exist in Dependency Track.";
	exit 1;
fi


# Function to upload to DD
dd_upload(){
    local dt=$(date +"%Y-%m-%d%H:%M:%S")
    local d=$(date +"%Y-%m-%d")
    # start date is 2 days after first contact
    local start_d=$(date +"%Y-%m-%d" -d "+2 days")
    # end date is 6 days after start date
    local end_d=$(date +"%Y-%m-%d" -d "$start_d+6 days")
    ###
    #1. Find project by listing all products and matching product name to dep-track project name
    #2. If a match found, use the product ID
    #3. Use following to create new engagement:
    #   - Repo URL
    #   - Build ID
    #   - Commit hash
    #   - Brnach-tag
    #   - First contacted = scan date
    #   - Start Date = 48 hours from scan time
    #   - End Date = 96 hours from scan time
    #   - Status = Not Started
    #   - Engagement Type = CI/CD
    #   - Product ID
    ###
    
    # List products
    local product_list="$(curl -k --silent -X GET "${DD_URL}/products/" \
                -H "accept: application/json" \
                -H "Authorization: ${DD_API_KEY}")"
    
    # List engagements
    local eng_list="$(curl -k --silent -X GET "${DD_URL}/engagements/" \
                -H "accept: application/json" \
                -H "Authorization: ${DD_API_KEY}")"
    # Find product Id based on product name
    BU=$(echo "${BU}" | base64 -d)
    PRODUCT_ID=$(echo "${product_list}" | jq '.results[] | select(.name == 'env.BU') | .id')
    # Find engagement name based on project name in dep track
    ENG_NAME=$(echo "${eng_list}" | jq '.results[] | select(.name == '${DT_PROJECT_NAME}') | .name')
    
    #echo ${PRODUCT_ID}
    if [ -z "$PRODUCT_ID" ]; then
        echo "BU does not exist in Defect Dojo.";
        exit 1;
    fi

    # If engagement does not exist, create engagement
    if [ -z "$ENG_NAME" ]; then
        # Remove double quotes from name
        ENG_NAME=$(echo "${DT_PROJECT_NAME//\"}")
        echo $ENG_NAME
        # Create engagement
        RES="$(curl -k -X POST "${DD_URL}/engagements/" \
        -H "accept: application/json" \
        -H "Content-Type: application/json" \
        -H "Authorization: ${DD_API_KEY}" \
        -d '{"tags": [ "Security" ],
            "name": "'${ENG_NAME}'",
            "description": "App Sec Engagement",
            "version": "1.0",
            "first_contacted": "'${d}'",
            "target_start": "'${start_d}'",
            "target_end": "'${end_d}'",
            "reason": "null",
            "threat_model": true,
            "api_test": true,
            "pen_test": true,
            "check_list": true,
            "status": "Not Started",
            "engagement_type": "CI/CD",
            "build_id": "'${BUILD_ID}'",
            "commit_hash": "'${COMMIT_ID}'",
            "branch_tag": "'${BRANCH}'",
            "source_code_management_uri": "'${REPO_URL}'",
            "deduplication_on_engagement": true,
            "product": "'${PRODUCT_ID}'" }'
            )"
    
        #echo ${RES}       
        if [ -z "$(echo $RES | jq '.id')" ]; then
            echo "Error: Could not create engagement."
            echo $RES;
            exit 1
        fi
        echo "Engagement created. Success."
        ENGAGEMENT_ID=$(echo "${RES}" | jq '.id')
        #echo ${ENGAGEMENT_ID}

        # # Create test
        # RES="$(curl -k -X POST "${DD_URL}/tests/" \
        # -H "accept: application/json" \
        # -H "Content-Type: application/json" \
        # -H "Authorization: ${DD_API_KEY}" \
        # -d '{"engagement": "'${ENGAGEMENT_ID}'",
        #     "tags": [ "DT", "SCA" ],
        #     "description": "Dep Track Scan",            
        #     "target_start": "'${start_d}'",
        #     "target_end": "'${end_d}'",
        #     "created": "'${dt}'",
        #     "test_type": 164}'
        #     )"
    
        # Import scan
        RES="$(curl -k --silent -H "Authorization: ${DD_API_KEY}" \
        -F "description=SCA Scan ($dt)" \
        -F "file=@sca_report.json" \
        -F "scan_date=${d}" \
        -F "minimum_severity=Info" \
        -F "active=true" \
        -F "verified=true" \
        -F "scan_type=Dependency Track Finding Packaging Format (FPF) Export" \
        -F "engagement=${ENGAGEMENT_ID}" \
        -F "tags=["SCA"]" \
        -F "close_old_findings=true" \
        "${DD_URL}/import-scan/")"

        if [ "$(echo $RES | jq '.scan_date')" == "" ]; then
            echo "Could not import SCA Scan report."
            echo $RES;
            exit 1
        fi
        echo "Scan report imported. Success."
        echo $RES
    else
        # Engagement exist, find specific test
        local test_list="$(curl -k --silent -X GET "${DD_URL}/tests/" \
                -H "accept: application/json" \
                -H "Authorization: ${DD_API_KEY}")"
        
        # Get engagement ID based on engagement name
        ENG_ID=$(echo "${eng_list}" | jq '.results[] | select(.name == '${DT_PROJECT_NAME}') | .id')
        # Get test ID based on engagement ID
        TEST_ID=$(echo "${test_list}" | jq '.results[] | select(.engagement == '${ENG_ID}') | .id')

        # Re-import scan to test ID
        echo $ENG_ID
        echo $TEST_ID
        # Re-import scan
        RES="$(curl -k --silent -H "Authorization: ${DD_API_KEY}" \
        -F "scan_date=${d}" \
        -F "minimum_severity=Info" \
        -F "active=true" \
        -F "verified=true" \
        -F "scan_type=Dependency Track Finding Packaging Format (FPF) Export" \
        -F "file=@sca_report.json" \
        -F "test=${TEST_ID}" \
        "${DD_URL}/reimport-scan/")"

        if [ "$(echo $RES | jq '.scan_date')" == "" ]; then
            echo "Could not import SCA Scan report."
            echo $RES;
            exit 1
        fi
        echo "Scan report re-imported. Success."
        echo $RES
    fi
}

if [[ ! -z $json_export ]]; then
    echo $json_export>sca_report.json
    ls -la
    # Import to Defect Dojo 
    dd_upload
    #result=$(dd_upload)
    #echo $result
else
    echo "Failed to get the json report from dependency track."
    exit 1
fi

# Output results
echo "Number of vulnerabilities:"
echo "Critical: $c"
echo "High: $h"
echo "Medium: $m"
echo "Low: $l"
echo "Unassigned: $u"


