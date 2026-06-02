defmodule Attached.Variants.VariantTransformWorker do
  @moduledoc """
  Oban worker that pre-processes a variant asynchronously.

  Useful for eagerly warming up variants after upload so the first
  `Attached.url/3` call returns the cached result immediately.

  ## Enqueueing

      Attached.Variants.VariantTransformWorker.new(%{
        "original_id" => original.id,
        "record_module" => "MyApp.Accounts.User",
        "field" => "avatar",
        "variant" => "thumb"
      })
      |> Oban.insert()

  The worker resolves the transform spec from the record module's schema
  declaration at perform time — no transform serialization, no
  string-to-atom round-trip on user-supplied keys.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  @impl true
  def perform(%Oban.Job{
        args: %{
          "original_id" => original_id,
          "record_module" => record_module,
          "field" => field,
          "variant" => variant
        }
      }) do
    module = Module.concat([record_module])
    field = lookup_atom!(module.__attached_fields__(), field, "field")

    transforms_for_variants = module.__attached_variants__(field)
    variant = lookup_atom!(Map.keys(transforms_for_variants), variant, "variant")

    transforms =
      transforms_for_variants
      |> Map.fetch!(variant)
      |> Keyword.put(:variant_name, variant)

    transform_digest = Attached.Variants.transform_digest(transforms)
    original = Attached.Originals.get!(original_id)

    Attached.Variants.process(original, transform_digest, transforms)
    :ok
  end

  # Resolves a string from the Oban payload back to one of the atoms the
  # schema declared. Avoids `String.to_existing_atom` — the atoms we accept
  # are exactly the ones the module exposes, no broader.
  defp lookup_atom!(known, input, label) do
    Enum.find(known, fn atom -> Atom.to_string(atom) == input end) ||
      raise ArgumentError,
            "unknown #{label}: #{inspect(input)} — known: #{inspect(known)}"
  end
end
