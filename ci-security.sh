#!/bin/bash
#set -x

# Set directory to search
DIR=$1
# Check project type: .NET (C# or cs) or python
if [[ -n $(find $DIR -name '*.csproj' -o -name '*.vbproj' -o -name 'packages.config' -o -name '*.sln') ]]; then
    echo "C# project"
    TYPE="C#"
elif [[ -n $(find $DIR -name '*.py') ]]; then
    echo "Python project"
    TYPE="Python"
else
    echo "Project type not supported."
    #exit 1
fi

case $TYPE in
    "C#")
        echo "Hello C#!"
        ;;

    "Python")
        echo "Hello python!"
        # Freeze requirements.txt
        pip freeze > requirements.txt 1>&2
        # Install cyclonedx to create sbom
        pip install --trusted-host pypi.org --trusted-host files.pythonhosted.org --trusted-host pypi.python.org cyclonedx-bom
        #3. Run it and it will generate sbom in current directory
        cyclonedx-py -i $DIR -o $DIR
        ls -ltr
        ;;

    *)
        echo ":("
esac
exit 0

# Install curl
#apt-get update
#apt-get install curl

#1. Freeze requirements.txt
pip freeze > requirements.txt 1>&2
#2. Install cyclonedx to create sbom
pip install --trusted-host pypi.org --trusted-host files.pythonhosted.org --trusted-host pypi.python.org cyclonedx-bom
#3. Run it and it will generate sbom in current directory
cyclonedx-py
ls -ltr

#4. Read project UUID from env
DEFAULT_UUID="2d395a41-d684-45c7-a8f9-92d602a43223"
DEFAULT_KEY="mJaqkPN9JFzFwAKGffU1uN6CuW5Uu5dU"
PROJECT_UUID=${PROJECT_UUID:-$DEFAULT_UUID}

API_KEY=${TEAM_KEY:-$DEFAULT_KEY}
# Generate base64 encoded bom without any whitespaces
b64bom=$(base64 -w 0 bom.xml)
echo $b64bom
#5. Post sbom to depenedency track
# curl -i -X "POST" "http://104.43.15.124:443/api/v1/bom" \
#         -H "Content-Type:multipart/form-data" \
#         -H "X-API-Key: ${API_KEY}" \
#         -F "project=${PROJECT_UUID}" \
#         -F "bom=${b64bom}"

curl -i -X "PUT" "http://104.43.15.124:443/api/v1/bom" \
        -H 'Content-Type: application/json' \
        -H "X-API-Key: ${API_KEY}" \
        -d '{
            "project": "'${PROJECT_UUID}'",
            "bom": "'${b64bom}'"
        }'