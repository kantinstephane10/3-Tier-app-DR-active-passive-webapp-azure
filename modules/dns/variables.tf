variable "resource_group_name" { type = string }
variable "zone_name" { type = string }
variable "host_label" { type = string }
variable "profile_id" { type = string }
variable "endpoint_id" { type = string }
variable "endpoint_hostname" { type = string }
variable "origin_group_id" { type = string }
variable "origin_ids" { type = list(string) }
variable "tags" { type = map(string) }

variable "firewall_policy_id" { type = string }
