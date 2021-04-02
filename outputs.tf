output "submit_url" {
  value       = "http://${aws_lb.submit.dns_name}"
  description = "Public ALB URL for submissions"
}
