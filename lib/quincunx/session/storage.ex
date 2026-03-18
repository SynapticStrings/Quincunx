defmodule Quincunx.Session.Storage do
  @moduledoc """
  Manages isolated storage configurations for a specific session.

  Since ETS tables are tied to the process that creates them, the
  Session Manager in the host application should call `new/0` and
  keep the returned struct in its state.
  """

  @type t :: %__MODULE__{
          meta_conf: {module(), term()},
          blob_conf: {module(), term()}
        }

  defstruct [:meta_conf, :blob_conf]

  @doc """
  Initializes a new, isolated local storage layer based on ETS.
  The calling process becomes the owner of these ETS tables.
  """
  @spec new() :: t()
  def new do
    meta_ref = OrchidStratum.MetaStorage.EtsAdapter.init()
    blob_ref = OrchidStratum.BlobStorage.EtsAdapter.init()

    %__MODULE__{
      meta_conf: {OrchidStratum.MetaStorage.EtsAdapter, meta_ref},
      blob_conf: {OrchidStratum.BlobStorage.EtsAdapter, blob_ref}
    }
  end

  @doc """
  Create a configuration from custom adapters (e.g., database-backed or out-of-core memory).
  """
  @spec new({module(), term()}, {module(), term()}) :: t()
  def new(meta_conf, blob_conf) do
    %__MODULE__{
      meta_conf: meta_conf,
      blob_conf: blob_conf
    }
  end
end
