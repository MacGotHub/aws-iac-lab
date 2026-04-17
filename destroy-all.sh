#!/bin/bash
set -e

LABS=(
  "opentofu/lab-10-ec2-w2"
  "opentofu/lab-06-ec2"
  "opentofu/lab-09-tgw-w2"
  "opentofu/lab-08-firewall-w2"
  "opentofu/lab-07-vpc-w2"
  "opentofu/lab-05-tgw"
  "opentofu/lab-04-firewall"
  "opentofu/lab-03-vpc"
  "opentofu/lab-02-vpn"
  "opentofu/lab-01-vpc"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for lab in "${LABS[@]}"; do
  echo ""
  echo "========================================="
  echo "Destroying: $lab"
  echo "========================================="
  cd "$SCRIPT_DIR/$lab"
  tofu destroy -auto-approve
done

echo ""
echo "All labs destroyed successfully."
