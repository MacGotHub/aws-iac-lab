output "tgw_w2_id" {
  value       = aws_ec2_transit_gateway.main.id
  description = "Transit Gateway ID in us-west-2"
}

output "peering_attachment_id" {
  value       = aws_ec2_transit_gateway_peering_attachment.west_to_east.id
  description = "TGW peering attachment ID"
}
