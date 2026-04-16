locals {
  sync_states = tolist(aws_networkfirewall_firewall.main.firewall_status[0].sync_states)
}

output "firewall_endpoint_az_a" {
  value       = [for s in local.sync_states : s.attachment[0].endpoint_id if s.availability_zone == "us-east-1a"][0]
  description = "Firewall VPC endpoint ID in us-east-1a"
}

output "firewall_endpoint_az_b" {
  value       = [for s in local.sync_states : s.attachment[0].endpoint_id if s.availability_zone == "us-east-1b"][0]
  description = "Firewall VPC endpoint ID in us-east-1b"
}
