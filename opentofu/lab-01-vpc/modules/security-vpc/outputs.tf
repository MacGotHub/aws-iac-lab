output "vpc_id" {
  value = aws_vpc.this.id
}

output "igw_id" {
  value = aws_internet_gateway.this.id
}

output "tgw_subnet_ids" {
  description = "TGW attachment subnet IDs keyed by AZ"
  value       = { for az, subnet in aws_subnet.tgw : az => subnet.id }
}

output "gwlbe_subnet_ids" {
  description = "GWLB endpoint subnet IDs keyed by AZ"
  value       = { for az, subnet in aws_subnet.gwlbe : az => subnet.id }
}

output "untrust_subnet_ids" {
  description = "Firewall untrust subnet IDs keyed by AZ"
  value       = { for az, subnet in aws_subnet.untrust : az => subnet.id }
}

output "trust_mgmt_subnet_ids" {
  description = "Firewall trust/mgmt subnet IDs keyed by AZ"
  value       = { for az, subnet in aws_subnet.trust_mgmt : az => subnet.id }
}

output "tgw_route_table_ids" {
  description = "Per-AZ TGW attachment subnet route table IDs — gwlb.tf adds the default route to the GWLB endpoint once it exists"
  value       = { for az, rt in aws_route_table.tgw : az => rt.id }
}

output "gwlbe_route_table_id" {
  description = "Shared GWLBE route table ID — tgw.tf adds RFC-1918 return routes to the TGW once it exists"
  value       = aws_route_table.gwlbe.id
}

output "untrust_route_table_id" {
  value = aws_route_table.untrust.id
}

output "main_route_table_id" {
  value = aws_route_table.main.id
}
