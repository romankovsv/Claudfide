variable "name" {
  description = "Storage account name. Lowercase letters and digits only, 3 to 24 characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "The name must be 3 to 24 lowercase letters or digits."
  }
}

variable "resource_group_name" {
  description = "Resource group that holds the account."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "replication_type" {
  description = "Replication type, for example LRS or GRS."
  type        = string
  default     = "LRS"
}

variable "is_data_lake" {
  description = "Turn on the hierarchical namespace for a data lake."
  type        = bool
  default     = false
}

variable "containers" {
  description = "Names of the blob containers to create."
  type        = set(string)
  default     = []
}

variable "allowed_subnet_ids" {
  description = "Subnets that may reach the account. Everything else is denied."
  type        = list(string)
  default     = []
}

variable "blob_delete_retention_days" {
  description = "Soft-delete retention for blobs, in days. Azure accepts 1 to 365."
  type        = number
  default     = 7

  validation {
    condition     = var.blob_delete_retention_days >= 1 && var.blob_delete_retention_days <= 365
    error_message = "blob_delete_retention_days must be between 1 and 365."
  }
}

variable "tags" {
  description = "Tags for all resources."
  type        = map(string)
  default     = {}
}
