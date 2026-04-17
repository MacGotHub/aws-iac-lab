output "north_public_ip" {
  value       = aws_instance.north.public_ip
  description = "Public IP of north instance"
}

output "south_public_ip" {
  value       = aws_instance.south.public_ip
  description = "Public IP of south instance"
}

output "north_private_ip" {
  value       = aws_instance.north.private_ip
  description = "Private IP of north instance"
}

output "south_private_ip" {
  value       = aws_instance.south.private_ip
  description = "Private IP of south instance"
}

output "ssh_key_path" {
  value       = local_sensitive_file.private_key_w2.filename
  description = "Path to the SSH private key"
}
