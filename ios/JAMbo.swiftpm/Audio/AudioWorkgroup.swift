import AudioToolbox
import Foundation

/// Аудио-группа выхода и потоки реального времени для помощников MULTICORE (RenderPool).
/// В Swift API аудио-групп закрыт («osWorkgroup is unavailable in Swift: Swift is not supported for use with audio
/// realtime threads»; os_workgroup_* не видны): группа — свойством выхода kAudioOutputUnitProperty_OSWorkgroup (2015)
/// через AudioUnitGetProperty, функции os_workgroup_* — через dlsym (публичные функции libSystem). Проверка 17.11:
/// с группой 8 Reverb на 1 / 2 / 3 потоках — 1,23 / 0,71 / 0,49 мс; без группы помощники просыпаются поздно
/// (1,10 / 1,04 мс) — без группы MULTICORE не включается.
struct AudioWorkgroup {
    typealias JoinFn = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Int32
    typealias LeaveFn = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Void
    typealias MaxFn = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Int32
    let group: UnsafeMutableRawPointer
    let join: JoinFn
    let leave: LeaveFn
    /// Потоков, которые группа советует (с самим аудиопотоком).
    let maxThreads: Int

    /// Группа выхода движка; нет группы или функций — nil.
    static func of(_ unit: AudioUnit?) -> AudioWorkgroup? {
        guard let u = unit else { return nil }
        var wg: UnsafeMutableRawPointer? = nil
        var size = UInt32(MemoryLayout<UnsafeMutableRawPointer?>.size)
        let r: OSStatus = AudioUnitGetProperty(u, AudioUnitPropertyID(2015), kAudioUnitScope_Global, 0, &wg, &size)
        guard r == noErr, let g = wg else { return nil }
        let all = UnsafeMutableRawPointer(bitPattern: -2)
        guard let j = dlsym(all, "os_workgroup_join"),
              let l = dlsym(all, "os_workgroup_leave"),
              let m = dlsym(all, "os_workgroup_max_parallel_threads") else { return nil }
        let maxFn: MaxFn = unsafeBitCast(m, to: MaxFn.self)
        return AudioWorkgroup(group: g, join: unsafeBitCast(j, to: JoinFn.self), leave: unsafeBitCast(l, to: LeaveFn.self),
                              maxThreads: Int(maxFn(g, nil)))
    }

    /// На потоке помощника: реальное время и вход в группу; возвращает выход из группы.
    func enter(sampleRate: Double) -> (() -> Void) {
        AudioWorkgroup.makeRealtime(sampleRate: sampleRate)
        // Токен входа (os_workgroup_join_token_s — 40 байт; с запасом).
        let token = UnsafeMutableRawPointer.allocate(byteCount: 128, alignment: 16)
        token.initializeMemory(as: UInt8.self, repeating: 0, count: 128)
        let ok: Bool = join(group, token) == 0
        let g = group
        let l = leave
        return {
            if ok { l(g, token) }
            token.deallocate()
        }
    }

    /// Поток реального времени (как аудиопоток): период — блок 256 отсчётов, расчёт — до половины.
    static func makeRealtime(sampleRate: Double) {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let toTicks: Double = Double(info.denom) / Double(info.numer)
        let periodNs: Double = 256 / sampleRate * 1e9
        var policy = thread_time_constraint_policy_data_t(
            period: UInt32(periodNs * toTicks),
            computation: UInt32(periodNs * 0.5 * toTicks),
            constraint: UInt32(periodNs * toTicks),
            preemptible: 1)
        let count = mach_msg_type_number_t(MemoryLayout<thread_time_constraint_policy_data_t>.size
                                           / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &policy) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { q in
                thread_policy_set(pthread_mach_thread_np(pthread_self()),
                                  thread_policy_flavor_t(THREAD_TIME_CONSTRAINT_POLICY), q, count)
            }
        }
    }
}
