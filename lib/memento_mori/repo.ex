defmodule MementoMori.Repo do
  use Ecto.Repo,
    otp_app: :memento_mori,
    adapter: Ecto.Adapters.Postgres
end
