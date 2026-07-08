defmodule MementoMoriWeb.CapsuleLiveTest do
  use MementoMoriWeb.ConnCase

  import Phoenix.LiveViewTest
  import MementoMori.VaultFixtures

  @create_attrs %{title: "some title", sensitivity_tier: "high"}
  @update_attrs %{title: "some updated title", sensitivity_tier: "low"}
  # sensitivity_tier is a select with no blank option; a blank title is enough
  # to make the form invalid.
  @invalid_attrs %{title: nil}

  setup :register_and_log_in_owner

  defp create_capsule(%{scope: scope}) do
    capsule = capsule_fixture(scope)

    %{capsule: capsule}
  end

  describe "Index" do
    setup [:create_capsule]

    test "lists all capsules", %{conn: conn, capsule: capsule} do
      {:ok, _index_live, html} = live(conn, ~p"/capsules")

      assert html =~ "Listing Capsules"
      assert html =~ capsule.title
    end

    test "saves new capsule", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/capsules")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Capsule")
               |> render_click()
               |> follow_redirect(conn, ~p"/capsules/new")

      assert render(form_live) =~ "New Capsule"

      assert form_live
             |> form("#capsule-form", capsule: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#capsule-form", capsule: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/capsules")

      html = render(index_live)
      assert html =~ "Capsule created successfully"
      assert html =~ "some title"
    end

    test "editing a capsule reflects in the listing", %{conn: conn, capsule: capsule} do
      # Edit now lives on the capsule console (Show), reached from a card.
      {:ok, show_live, _html} = live(conn, ~p"/capsules/#{capsule}")

      assert {:ok, form_live, _html} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/capsules/#{capsule}/edit?return_to=show")

      assert render(form_live) =~ "Edit Capsule"

      assert form_live
             |> form("#capsule-form", capsule: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, _show_live, _html} =
               form_live
               |> form("#capsule-form", capsule: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/capsules/#{capsule}")

      {:ok, _index_live, html} = live(conn, ~p"/capsules")
      assert html =~ "some updated title"
    end

    test "deletes a capsule from the console", %{conn: conn, capsule: capsule} do
      # Delete now lives on the capsule console (Show), not the listing.
      {:ok, show_live, _html} = live(conn, ~p"/capsules/#{capsule}")

      assert {:ok, index_live, _html} =
               show_live
               |> element("a", "Delete")
               |> render_click()
               |> follow_redirect(conn, ~p"/capsules")

      refute has_element?(index_live, "#capsules-#{capsule.id}")
    end
  end

  describe "Show" do
    setup [:create_capsule]

    test "displays capsule", %{conn: conn, capsule: capsule} do
      {:ok, _show_live, html} = live(conn, ~p"/capsules/#{capsule}")

      assert html =~ "Show Capsule"
      assert html =~ capsule.title
    end

    test "updates capsule and returns to show", %{conn: conn, capsule: capsule} do
      {:ok, show_live, _html} = live(conn, ~p"/capsules/#{capsule}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/capsules/#{capsule}/edit?return_to=show")

      assert render(form_live) =~ "Edit Capsule"

      assert form_live
             |> form("#capsule-form", capsule: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#capsule-form", capsule: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/capsules/#{capsule}")

      html = render(show_live)
      assert html =~ "Capsule updated successfully"
      assert html =~ "some updated title"
    end
  end
end
