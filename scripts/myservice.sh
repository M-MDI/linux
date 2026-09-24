#!/bin/bash

# This script monitors root disk usage continuously.
# It loops forever, doing work and then sleeping.

while true; do
  echo "Disk Usage at $(date):"
  df -h /
  sleep 60
done
