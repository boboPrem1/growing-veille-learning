# Les sauvegardes de la base : chez le FOURNISSEUR (hors de nos régions, elles survivent à leur
# perte), chiffrées CÔTÉ CLIENT par pgBackRest (le fournisseur ne peut rien lire), avec l'archivage
# continu des WAL : on peut restaurer à la seconde près (PITR).

provider "aws" {
  alias                       = "fournisseur" # le S3 managé du fournisseur (https://s3.fournisseur.test)
  region                      = "us-east-1"
  profile                     = "fournisseur"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  endpoints {
    s3  = "https://s3.fournisseur.test"
    iam = "https://s3.fournisseur.test"
  }
}

resource "aws_s3_bucket" "sauvegardes" {
  provider = aws.fournisseur
  bucket   = "marche-sauvegardes"
}

# un utilisateur pour pgBackRest, qui ne voit QUE ce bucket
resource "aws_iam_user" "pgbackrest" {
  provider = aws.fournisseur
  name     = "marche-pgbackrest"
}
resource "aws_iam_user_policy" "pgbackrest" {
  provider = aws.fournisseur
  name     = "sauvegardes"
  user     = aws_iam_user.pgbackrest.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:ListBucket"], Resource = [aws_s3_bucket.sauvegardes.arn] },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = ["${aws_s3_bucket.sauvegardes.arn}/*"] },
    ]
  })
}
resource "aws_iam_access_key" "pgbackrest" {
  provider = aws.fournisseur
  user     = aws_iam_user.pgbackrest.name
}
resource "random_password" "chiffrement_sauvegardes" { # la clé de chiffrement côté client
  length  = 48
  special = false
}

# rangé dans le coffre ; la base le lit avec SON certificat (rôle « db »)
resource "vault_kv_secret_v2" "pgbackrest" {
  mount = vault_mount.kv.path
  name  = "marche/pgbackrest"
  data_json = jsonencode({
    access_key  = aws_iam_access_key.pgbackrest.id
    secret_key  = aws_iam_access_key.pgbackrest.secret
    chiffrement = random_password.chiffrement_sauvegardes.result
  })
}
resource "vault_policy" "db" {
  name   = "db"
  policy = <<-EOT
    path "kv/data/marche/pgbackrest" { capabilities = ["read"] }
  EOT
}
resource "vault_cert_auth_backend_role" "db" {
  name                 = "db"
  backend              = vault_auth_backend.cert.path
  certificate          = local.regions.ac_intermediaire
  allowed_common_names = ["db*.marche.test"]
  token_policies       = [vault_policy.db.name, vault_policy.identite["db"].name] # + son identité de service (Palier 3)
  token_ttl            = 3600
}
