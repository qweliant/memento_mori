defmodule MementoMori.Timelock.Drand do
  @moduledoc """
  drand quicknet round math.

  quicknet is the timelock-capable drand network (unchained, BLS on G1). These
  constants let the server compute the same round the browser's tlock-js does, so
  a capsule's access contract and the artifacts sealed to it agree on the unlock
  moment.
  """

  @quicknet_genesis 1_692_803_367
  @quicknet_period 3

  @doc "The drand quicknet round active at (or just before) the given instant."
  def round_at(%DateTime{} = dt) do
    t = DateTime.to_unix(dt)
    if t <= @quicknet_genesis, do: 1, else: div(t - @quicknet_genesis, @quicknet_period) + 1
  end

  @doc "Approximate wall-clock instant a drand quicknet round is emitted."
  def round_time(round) when is_integer(round) and round > 0 do
    DateTime.from_unix!(@quicknet_genesis + (round - 1) * @quicknet_period)
  end
end
