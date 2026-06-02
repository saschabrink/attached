defmodule Attached.Ecto.Schema do
  @moduledoc """
  Macros for declaring file attachments on Ecto schemas.

  ## Usage

      defmodule MyApp.Accounts.User do
        use Ecto.Schema
        use Attached.Ecto.Schema

        schema "users" do
          field :name, :string

          attached :avatar, variants: %{
            thumb: [resize_to_fill: {100, 100}],
            medium: [resize_to_limit: {400, 400}]
          }
        end
      end

  ## FK column naming

  `attached :avatar` expects an `avatar_attached_original_id` FK column by default.

  Override per field:  `attached :avatar, foreign_key: :avatar_original_id`
  Override globally:   `config :attached, default_foreign_key_suffix: "_original_id"`

  ## Multiple attachments

  For multi-file attachments, declare a plain Ecto join schema with its
  own `belongs_to :original, Attached.Originals.Original` association — that gives
  you a real schema for positions, captions, soft deletes, and ad-hoc
  queries without fighting a hidden join table.
  """

  defmacro __using__(_opts) do
    quote do
      import Attached.Ecto.Schema, only: [attached: 1, attached: 2]
      import Attached.Ecto.Changeset, only: [put_attached: 3]

      Module.register_attribute(__MODULE__, :__attached_config__, accumulate: true)
      @before_compile Attached.Ecto.Schema
    end
  end

  @doc """
  Declares a single file attachment on the schema.

  Generates a `belongs_to :{name}_attached_original` association and expects a
  `{name}_attached_original_id` FK column by default (configurable).

  ## Options

    * `:foreign_key` — override the FK column name (atom)
    * `:variants` — map of variant name to transformation options

  ## Example

      attached :avatar, variants: %{thumb: [resize_to_fill: {100, 100}]}
  """
  defmacro attached(name, opts \\ []) do
    original_assoc = :"#{name}_attached_original"
    {opts_value, _} = Code.eval_quoted(opts, [], __CALLER__)

    fk_suffix = Application.get_env(:attached, :default_foreign_key_suffix, "_attached_original_id")
    fk = Keyword.get(opts_value, :foreign_key, :"#{name}#{fk_suffix}")
    enriched_opts = Keyword.put(opts_value, :foreign_key, fk)

    quote do
      belongs_to(unquote(original_assoc), Attached.Originals.Original,
        type: :binary_id,
        foreign_key: unquote(fk)
      )

      @__attached_config__ {unquote(name), unquote(Macro.escape(enriched_opts))}
    end
  end

  defmacro __before_compile__(env) do
    configs = Module.get_attribute(env.module, :__attached_config__)

    quote do
      @doc false
      def __attached_config__ do
        unquote(Macro.escape(configs))
      end

      @doc false
      def __attached_config__(field) do
        Enum.find(__attached_config__(), fn {name, _opts} -> name == field end)
      end

      @doc false
      def __attached_fields__ do
        Enum.map(__attached_config__(), fn {name, _opts} -> name end)
      end

      @doc false
      def __attached_variants__(field) do
        case __attached_config__(field) do
          {_, opts} -> Keyword.get(opts, :variants, %{})
          nil -> %{}
        end
      end
    end
  end
end
