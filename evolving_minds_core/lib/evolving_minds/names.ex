defmodule EvolvingMinds.Names do
  @moduledoc """
  Procedural names for minds, so the world reads as a story instead of
  hex dumps. Names are decorative: identity stays the entity id.
  """

  @prefixes ~w(Kor Vel Thre Mel Nor Zar Qui Ash Bel Dra Fen Gal Hex Ily
               Jor Lys Myr Nyx Ori Pax Ryn Syl Tor Vor Wren Xan Yll Zen
               Cal Dun Eri Fael Gwyn Hal Isk Kaz Lum Mor Nev Osk)
  @middles ~w(a e i o u ar en ir or ul ys)
  @suffixes ~w(vax ia dor ith ra el os une yx en is or un ael ix a yn ex
               eth im on ur ien ak)

  def generate do
    middle = if :rand.uniform() > 0.7, do: Enum.random(@middles), else: ""
    Enum.random(@prefixes) <> middle <> Enum.random(@suffixes)
  end
end
