variable "subscription_id" {
  type = string
}
variable "tenant_id" {
  type = string
}
variable "prefix" {
  type    = string
  default = "kt-lab"
}
variable "unique_suffix" {
  type = string
}
variable "stage" {
  type    = string
  default = "foundation"
  validation {
    condition     = contains(["foundation", "primary", "dr", "edge"], var.stage)
    error_message = "Select foundation, primary, dr, or edge."
  }
}
variable "ssh_public_key" {
  type = string
}
variable "sql_admin_login" {
  type = string
}
variable "sql_admin_object_id" {
  type = string
}
variable "vm_size" {
  type    = string
  default = "Standard_D2s_v5"
}
variable "sql_sku" {
  type    = string
  default = "BC_Gen5_2"
}
variable "enable_bastion" {
  type    = bool
  default = true
}
variable "enable_nat" {
  type    = bool
  default = true
}
variable "sql_zone_redundant" {
  type    = bool
  default = true
}
variable "tags" {
  type    = map(string)
  default = { owner = "Kantin Tongue", project = "azure-three-tier", environment = "lab" }
}

variable "standby_vm_size" {
  type    = string
  default = "Standard_B2s"
}

variable "dns_zone_name" {
  type        = string
  default     = ""
  description = "Optional domain you own. Empty uses the Azure Front Door default hostname."
}
variable "dns_host_label" {
  type    = string
  default = "app"
}
