output "firewall_endpoint_id" {
  value       = tolist(aws_networkfirewall_firewall.main.firewall_status[0].sync_states)[0].attachment[0].endpoint_id
  description = "The VPC endpoint ID of the Network Firewall"
}
