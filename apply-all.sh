#!/bin/bash
set -e

LABS=(
  "opentofu/lab-01-vpc"
  "opentofu/lab-02-vpn"
  "opentofu/lab-03-vpc"
  "opentofu/lab-04-firewall"
  "opentofu/lab-05-tgw"
  "opentofu/lab-06-ec2"
  "opentofu/lab-07-vpc-w2"
  "opentofu/lab-08-firewall-w2"
  "opentofu/lab-09-tgw-w2"
  "opentofu/lab-10-ec2-w2"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for lab in "${LABS[@]}"; do
  echo ""
  echo "========================================="
  echo "Applying: $lab"
  echo "========================================="
  cd "$SCRIPT_DIR/$lab"
  tofu apply -auto-approve
done

echo ""
echo "All labs applied successfully."
