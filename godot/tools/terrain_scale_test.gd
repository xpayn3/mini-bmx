extends SceneTree
## chunk-build throughput vs worker count, and main-thread height() cost while they run
func _init():
	TerrainGeo.ensure()
	TerrainChunkBuilder.ensure_static()
	var f := TerrainField.new()
	f.setup(12345)
	var main_f := f.fork()
	for seg in [64, 96]:
		for n in [1, 2, 3, 4, 6]:
			var bs := []
			var tasks := []
			var total: int = n * 3
			var t0 := Time.get_ticks_usec()
			var next := 0
			var done := 0
			# keep n jobs in flight, 3n chunks total; time height() on the main thread meanwhile
			var hs := 0.0
			var hcalls := 0
			var hus := 0
			while done < total:
				while tasks.size() < n and next < total:
					var b := TerrainChunkBuilder.new(f.fork(), next % 7 - 3, next / 7 - 1, seg, 0)
					bs.append(b)
					tasks.append(WorkerThreadPool.add_task(b.run, false))
					next += 1
				var h0 := Time.get_ticks_usec()
				for i in 200:
					hs += main_f.deck(300.0 + hcalls * 0.013, 5.0 + (hcalls % 50) * 0.01)
					hcalls += 1
				hus += Time.get_ticks_usec() - h0
				var keep := []
				for t in tasks:
					if WorkerThreadPool.is_task_completed(t):
						WorkerThreadPool.wait_for_task_completion(t)
						done += 1
					else:
						keep.append(t)
				tasks = keep
			var wall := (Time.get_ticks_usec() - t0) / 1000.0
			print("seg %d, %d workers: %.1f chunks/s (%.0f ms each), main-thread deck() %.1f us/call" % [seg, n, total / (wall / 1000.0), wall / total * n, float(hus) / hcalls])
	quit()
