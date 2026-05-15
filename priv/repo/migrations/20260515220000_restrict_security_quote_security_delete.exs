defmodule Portfolixir.Repo.Migrations.RestrictSecurityQuoteSecurityDelete do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE security_quotes
    DROP CONSTRAINT security_quotes_security_id_fkey,
    ADD CONSTRAINT security_quotes_security_id_fkey
    FOREIGN KEY (security_id)
    REFERENCES securities(id)
    ON DELETE RESTRICT
    """)
  end

  def down do
    execute("""
    ALTER TABLE security_quotes
    DROP CONSTRAINT security_quotes_security_id_fkey,
    ADD CONSTRAINT security_quotes_security_id_fkey
    FOREIGN KEY (security_id)
    REFERENCES securities(id)
    ON DELETE CASCADE
    """)
  end
end
