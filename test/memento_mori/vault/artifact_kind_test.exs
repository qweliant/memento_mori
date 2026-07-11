defmodule MementoMori.Vault.ArtifactKindTest do
  use ExUnit.Case, async: true

  alias MementoMori.Vault.ArtifactKind

  describe "at_least/2 (the sensitivity floor rule)" do
    test "raises a lower tier up to the floor" do
      assert ArtifactKind.at_least(:low, :high) == :high
      assert ArtifactKind.at_least(:low, :medium) == :medium
    end

    test "never lowers a tier the owner already raised" do
      assert ArtifactKind.at_least(:high, :low) == :high
      assert ArtifactKind.at_least(:medium, :low) == :medium
    end

    test "is a no-op when already at the floor" do
      assert ArtifactKind.at_least(:high, :high) == :high
    end
  end

  describe "templates" do
    test "every kind resolves to a valid floor and release strategy" do
      for kind <- ArtifactKind.kinds() do
        assert ArtifactKind.sensitivity_floor(kind) in [:low, :medium, :high]
        assert ArtifactKind.release_strategy(kind) in [:deliver, :threshold_reconstruct]
      end
    end

    test "secrets take the threshold-reconstruct path; a letter is just delivered" do
      assert ArtifactKind.release_strategy(:secret_key) == :threshold_reconstruct
      assert ArtifactKind.release_strategy(:letter) == :deliver
    end

    test "high-stakes kinds impose a high floor" do
      assert ArtifactKind.sensitivity_floor(:will) == :high
      assert ArtifactKind.sensitivity_floor(:secret_key) == :high
      assert ArtifactKind.sensitivity_floor(:generic) == :low
    end

    test "required_fields returns only the fields flagged required" do
      assert :executor in ArtifactKind.required_fields(:will)
      assert :jurisdiction in ArtifactKind.required_fields(:will)
      # supersedes is optional
      refute :supersedes in ArtifactKind.required_fields(:will)
      assert ArtifactKind.required_fields(:generic) == []
    end
  end
end
