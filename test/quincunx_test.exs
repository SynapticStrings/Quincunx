defmodule QuincunxTest do
  use ExUnit.Case
  doctest Quincunx

  test "greets the world" do
    assert Quincunx.hello() == :world
  end
end
