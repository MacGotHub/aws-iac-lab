output "east_public_ip" {
  value       = aws_instance.east.public_ip
  description = "Public IP of east instance"
}

output "west_public_ip" {
  value       = aws_instance.west.public_ip
  description = "Public IP of west instance"
}

output "east_private_ip" {
  value       = aws_instance.east.private_ip
  description = "Private IP of east instance"
}

output "west_private_ip" {
  value       = aws_instance.west.private_ip
  description = "Private IP of west instance"
}

output "ssh_key_path" {
  value       = local_sensitive_file.private_key.filename
  description = "Path to the SSH private key"
}
