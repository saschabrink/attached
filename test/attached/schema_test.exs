defmodule Attached.Ecto.SchemaTest do
  use ExUnit.Case, async: true

  alias Attached.Test.User

  describe "attached/2 macro" do
    test "generates belongs_to association" do
      assert :avatar_attached_original in User.__schema__(:associations)
    end
  end

  describe "__attached_config__/0" do
    test "lists all attachment fields" do
      configs = User.__attached_config__()
      assert length(configs) == 1

      names = Enum.map(configs, fn {name, _opts} -> name end)
      assert :avatar in names
    end
  end

  describe "__attached_config__/1" do
    test "returns config for a specific field" do
      assert {:avatar, opts} = User.__attached_config__(:avatar)
      assert %{thumb: _, medium: _} = Keyword.get(opts, :variants)
    end

    test "returns nil for unknown field" do
      assert User.__attached_config__(:nonexistent) == nil
    end
  end

  describe "__attached_variants__/1" do
    test "returns variant definitions" do
      variants = User.__attached_variants__(:avatar)
      assert %{thumb: [resize_to_fill: {100, 100}]} = variants
    end
  end

  describe "__attached_fields__/0" do
    test "lists all attachment field names" do
      assert :avatar in User.__attached_fields__()
    end
  end
end
