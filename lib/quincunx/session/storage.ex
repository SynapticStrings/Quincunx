defmodule Quincunx.Session.Storage do
  @moduledoc """
  Manages isolated storage configurations for a specific session.

  Since ETS tables are tied to the process that creates them, the
  Session Manager in the host application should call `new/0` and
  keep the returned struct in its state.
  """

  @type storage :: term()

  @type t :: %__MODULE__{
          meta_conf: {module(), storage()},
          blob_conf: {module(), storage()}
        }

  defstruct [:meta_conf, :blob_conf]

  @doc """
  Initializes a new, isolated local storage layer based on ETS.
  The calling process becomes the owner of these ETS tables.
  """
  @spec new() :: t()
  def new do
    new(
      {
        OrchidStratum.MetaStorage.EtsAdapter,
        fn -> OrchidStratum.MetaStorage.EtsAdapter.init() end
      },
      {OrchidStratum.BlobStorage.EtsAdapter,
       fn -> OrchidStratum.BlobStorage.EtsAdapter.init() end}
    )
  end

  @doc """
  Create a configuration from custom adapters.
  """
  def new({meta_mod, meta_factory}, {blob_mod, blob_factory})
      when is_function(meta_factory) and is_function(blob_factory) do
    meta_ref = meta_factory.()
    blob_ref = blob_factory.()

    %__MODULE__{
      meta_conf: {meta_mod, meta_ref},
      blob_conf: {blob_mod, blob_ref}
    }
  end

  @spec new({module(), term()}, {module(), term()}) :: t()
  def new(meta_conf, blob_conf) do
    %__MODULE__{
      meta_conf: meta_conf,
      blob_conf: blob_conf
    }
  end
end
