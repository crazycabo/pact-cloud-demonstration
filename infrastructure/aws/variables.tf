variable "region" {
  default = "us-east-1"
}

variable "tags" {
  description = "Set list of custom tags, if required."
  type        = map(string)
  default     = {
    project   = "pact"
  }
}
