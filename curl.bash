#!/bin/bash

# Check if the ids.txt file exists
if [ ! -f "ids.txt" ]; then
    echo "Error: ids.txt file not found"
    exit 1
fi

# Create a directory for the JSON files if it doesn't exist
mkdir -p vehicle_data

# Read each line from ids.txt and process it
while read -r vehicle_id; do
    # Skip empty lines
    if [ -z "$vehicle_id" ]; then
        continue
    fi
    
    echo "Fetching data for vehicle ID: $vehicle_id"
    
    # Make curl request and save to a JSON file named after the ID
    curl -s "https://busdata.cs.pdx.edu/api/getBreadCrumbs?vehicle_id=$vehicle_id" > "vehicle_data/$vehicle_id.json"
    
    # Check if the curl command was successful
    if [ $? -eq 0 ]; then
        echo "Successfully saved data to vehicle_data/$vehicle_id.json"
    else
        echo "Error fetching data for vehicle ID: $vehicle_id"
    fi
    
    # Add a small delay to avoid overwhelming the server
    sleep 1
    
done < "ids.txt"

echo "All vehicle data has been downloaded."