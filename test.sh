#!/bin/bash

DIR=$1
if [[ -n $(find $DIR -maxdepth 1 -type f  -name "*.sln" -o -name "*.csproj" -o -name "*.vbproj" -o -name "packages.config") ]]; then
    echo "C# project"
    TYPE="C#"
elif [[ -n $(find $DIR -maxdepth 1 -type f -name "*.py") ]]; then
    echo "Python project"
    TYPE="Python"
elif [[ -n $(find $DIR -maxdepth 1 -type f -name "package.json" -o -name "yarn.lock") ]]; then
    echo "NodeJS project"
    TYPE="Node"
fi