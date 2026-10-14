# OpenBao : comment une instance d'application obtient ses secrets, SANS qu'aucun secret ne soit
# écrit dans son « user data ».
#  1. elle s'authentifie avec son CERTIFICAT client (émis par la couche « regions »), comme une
#     instance cloud avec un rôle IAM ;
#  2. elle reçoit un jeton limité par la politique « app » ;
#  3. elle lit des identifiants PostgreSQL TEMPORAIRES (1 h), créés à la demande et révoqués seuls,
#     et ses clés S3 (coffre « kv »).

# ------------------------------------------------------------------ l'identité : un certificat
resource "vault_auth_backend" "cert" {
  type = "cert"
  path = "cert"
}
resource "vault_cert_auth_backend_role" "app" {
  name                 = "app"
  backend              = vault_auth_backend.cert.path
  certificate          = local.regions.ac_intermediaire # l'AC qui a signé les certificats des instances
  allowed_common_names = ["app*.marche.test"]
  token_policies       = [vault_policy.app.name]
  token_ttl            = 3600
}

# ------------------------------------------------------------------ ce qu'une application peut lire
resource "vault_policy" "app" {
  name   = "app"
  policy = <<-EOT
    path "base/creds/app"         { capabilities = ["read"] }
    path "kv/data/marche/s3-app"  { capabilities = ["read"] }
  EOT
}

# ------------------------------------------------------------------ des identifiants de base temporaires
resource "vault_database_secrets_mount" "base" {
  path = "base"
  postgresql {
    name              = "marche"
    connection_url    = "postgresql://{{username}}:{{password}}@db.marche.test:5432/marche" # suit la primaire (bascule)
    username          = "bao"
    password          = local.regions.bao_db_mdp
    allowed_roles     = ["app"]
    verify_connection = true
  }
}
resource "vault_database_secret_backend_role" "app" {
  backend     = vault_database_secrets_mount.base.path
  name        = "app"
  db_name     = "marche"
  default_ttl = 3600
  max_ttl     = 86400
  # Chaque compte temporaire HÉRITE du rôle « marche » et l'ENDOSSE à la connexion (SET role) :
  # sans cela, le premier compte créerait les tables à son nom, et le suivant n'y aurait plus accès.
  creation_statements = [
    "CREATE ROLE \"{{name}}\" LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' IN ROLE marche;",
    "ALTER ROLE \"{{name}}\" SET role = 'marche';",
  ]
  # PostgreSQL 16 : le créateur (bao) n'a que l'option ADMIN sur le compte — pas ses privilèges, que
  # REASSIGN/DROP OWNED exigent (« permission denied to reassign objects »). Il se les accorde d'abord.
  # Et si le compte n'existe plus (base restaurée à un instant ANTÉRIEUR à sa création), la révocation
  # doit quand même réussir — sinon le bail reste bloqué pour toujours : d'où le « IF EXISTS ».
  # (OpenBao envoie chaque élément de la liste d'un bloc : les « ; » du DO ne le coupent pas — vérifié.)
  revocation_statements = [chomp(<<-EOT
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '{{name}}') THEN
        GRANT "{{name}}" TO bao WITH INHERIT TRUE;
        -- DROP ROLE ne coupe PAS les connexions déjà ouvertes (le pool de l'application) : un
        -- identifiant révoqué fonctionnerait encore des heures. On les termine.
        PERFORM pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename = '{{name}}';
        REASSIGN OWNED BY "{{name}}" TO marche;
        DROP OWNED BY "{{name}}";
        DROP ROLE "{{name}}";
      END IF;
    END $$;
  EOT
  )] # chomp : OpenBao rend le texte sans le saut de ligne final de l'heredoc — sans lui, un faux
  # « changement » à CHAQUE plan (une dérive permanente masque les vraies)
}

# ------------------------------------------------------------------ les autres secrets (clés S3)
resource "vault_mount" "kv" {
  path    = "kv"
  type    = "kv"
  options = { version = "2" }
}
resource "vault_kv_secret_v2" "s3_app" {
  mount = vault_mount.kv.path
  name  = "marche/s3-app"
  data_json = jsonencode({
    access_key = aws_iam_access_key.app.id
    secret_key = aws_iam_access_key.app.secret
  })
}
