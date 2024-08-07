count = 1_000
# values = Enum.map(1..count, &{"var_#{&1}", &1})

Application.ensure_all_started(:cachex)
Cachex.start(:cachex_cache)
ConCache.start_link(name: :con_cache, ttl_check_interval: false)
Finitomata.Cache.start_link(id: :infini_cache_naive, type: Infinitomata, ttl: 5_000, live?: true)
Finitomata.Cache.start_link(id: :fini_cache_naive, type: Finitomata, ttl: 5_000, live?: true)
Finitomata.Cache.start_link(id: :infini_cache, type: Infinitomata, ttl: 5_000, live?: true)
Finitomata.Cache.start_link(id: :fini_cache, type: Finitomata, ttl: 5_000, live?: true)

Enum.each(1..count, fn i ->
  ConCache.put(:con_cache, "var_#{i}", i)
  Finitomata.Cache.get_naive(:fini_cache_naive, "var_#{i}", getter: fn -> i end)
  Finitomata.Cache.get_naive(:infini_cache_naive, "var_#{i}", getter: fn -> i end)
  Finitomata.Cache.get(:fini_cache, "var_#{i}", getter: fn -> i end)
  Finitomata.Cache.get(:infini_cache, "var_#{i}", getter: fn -> i end)
  Cachex.put(:cachex_cache, "var_#{i}", i)
end)

Benchee.run(
  %{
    "con_cache" => fn ->
      Enum.each(count..1//-1, fn i ->
        ^i = ConCache.get(:con_cache, "var_#{i}")
      end)
    end,
    "finitomata_cache_naive" => fn ->
      Enum.each(count..1//-1, fn i ->
        {_, ^i} = Finitomata.Cache.get_naive(:fini_cache_naive, "var_#{i}")
      end)
    end,
    "infinitomata_cache_naive" => fn ->
      Enum.each(count..1//-1, fn i ->
        {_, ^i} = Finitomata.Cache.get_naive(:infini_cache_naive, "var_#{i}")
      end)
    end,
    "finitomata_cache" => fn ->
      Enum.each(count..1//-1, fn i ->
        {_, ^i} = Finitomata.Cache.get(:fini_cache, "var_#{i}")
      end)
    end,
    "infinitomata_cache" => fn ->
      Enum.each(count..1//-1, fn i ->
        {_, ^i} = Finitomata.Cache.get(:infini_cache, "var_#{i}")
      end)
    end,
    "cachex" => fn ->
      Enum.each(count..1//-1, fn i ->
        {:ok, ^i} = Cachex.get(:cachex_cache, "var_#{i}")
      end)
    end
  },
  time: 10,
  memory_time: 2
)
