# Ce que les autres couches ont besoin de savoir (lu par terraform_remote_state).
output "s3_admin_secret" {
  value     = random_password.s3_admin.result
  sensitive = true
}
output "bao_db_mdp" {
  value     = random_password.bao_db.result
  sensitive = true
}
output "ac_intermediaire" {
  value = local.ac_cert
}
output "machines" {
  description = "nom → rôle, région"
  value       = { for n, m in local.machines : n => { role = m.role, region = m.region } }
}
output "pdns_api" {
  value     = random_password.pdns_api.result
  sensitive = true
}
