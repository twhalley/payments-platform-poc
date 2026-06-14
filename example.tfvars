# Copy to terraform.tfvars (gitignored!) and fill in real values.
# terraform plan -var-file=terraform.tfvars
project_id        = "my-gcp-project-id"
region            = "europe-west2"
cluster_name      = "payments-poc"
node_machine_type = "e2-standard-4"
min_node_count    = 1
max_node_count    = 5
kms_keyring       = "payments-poc-keyring"
