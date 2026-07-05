defmodule MementoMori.Accounts.OwnerNotifier do
  import Swoosh.Email

  alias MementoMori.Mailer
  alias MementoMori.Accounts.Owner

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"MementoMori", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a owner email.
  """
  def deliver_update_email_instructions(owner, url) do
    deliver(owner.email, "Update email instructions", """

    ==============================

    Hi #{owner.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(owner, url) do
    case owner do
      %Owner{confirmed_at: nil} -> deliver_confirmation_instructions(owner, url)
      _ -> deliver_magic_link_instructions(owner, url)
    end
  end

  defp deliver_magic_link_instructions(owner, url) do
    deliver(owner.email, "Log in instructions", """

    ==============================

    Hi #{owner.email},

    You can log into your account by visiting the URL below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end

  defp deliver_confirmation_instructions(owner, url) do
    deliver(owner.email, "Confirmation instructions", """

    ==============================

    Hi #{owner.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end
end
