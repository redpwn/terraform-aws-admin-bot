variable "prefix" {
  type        = string
  default     = "admin-bot"
  description = "Prefix for all AWS resources created by the module"
}
variable "visit_cidr" {
  type        = string
  default     = "10.13.37.0/24"
  description = "CIDR for visit container VPC and subnet"
}
variable "image" {
  type        = string
  description = "Docker image URI on ECR with redpwn/admin-bot base"
}
variable "recaptcha" {
  type = object({
    site   = string
    secret = string
  })
  default = {
    site   = null
    secret = null
  }
  sensitive   = true
  description = "Google reCAPTCHA credentials"
}
variable "submit_max_scale" {
  type        = number
  default     = 100
  description = "Maximum concurrent submit instances"
}
variable "visit_scale" {
  type        = number
  default     = 1
  description = "Concurrent visit instances"
}
