defmodule Quincunx.Storage do
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

  alias OrchidStratum.MetaStorage.EtsAdapter, as: EtsMetaStorage
  alias OrchidStratum.BlobStorage.EtsAdapter, as: EtsBlobStorage

  @doc """
  Initializes a new, isolated local storage layer based on ETS.
  The calling process becomes the owner of these ETS tables.
  """
  @spec new() :: t()
  def new do
    meta_ref = EtsMetaStorage.init()
    blob_ref = EtsBlobStorage.init()

    new(
      {EtsMetaStorage, meta_ref},
      {EtsBlobStorage, blob_ref}
    )
  end

  @doc """
  Create a configuration from custom adapters.
  """
  @spec new({module(), term()}, {module(), term()}) :: t()
  def new(meta_conf, blob_conf) do
    %__MODULE__{
      meta_conf: meta_conf,
      blob_conf: blob_conf
    }
  end
end
