// Best-effort helper to make Bluetooth headset microphones usable for live
// capture on Linux/PipeWire (Arch and similar). A BT headset commonly comes
// up in the "a2dp-sink" profile (high-fidelity playback only, no mic input);
// this switches it to a handsfree profile ("headset-head-unit", codec mSBC
// when available) for the duration of the program, and restores whatever
// profile was active before on exit.
//
// Implemented via fork+execvp of `pactl` (no shell involved, so there is no
// command-injection risk even though the card name comes from parsing
// `pactl`'s own output). If `pactl` is not installed, or there is no
// Bluetooth card, every call here is a silent no-op.
#pragma once

#include <cctype>
#include <cstdio>
#include <sstream>
#include <string>
#include <vector>

#include <sys/wait.h>
#include <unistd.h>

namespace bt_profile {

namespace detail {

inline bool run(const std::vector<std::string> & argv, bool silent = true) {
    pid_t pid = fork();
    if (pid < 0) {
        return false;
    }
    if (pid == 0) {
        if (silent) {
            freopen("/dev/null", "w", stdout);
            freopen("/dev/null", "w", stderr);
        }
        std::vector<char *> args;
        args.reserve(argv.size() + 1);
        for (const auto & a : argv) {
            args.push_back(const_cast<char *>(a.c_str()));
        }
        args.push_back(nullptr);
        execvp(args[0], args.data());
        _exit(127);
    }
    int status = 0;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

inline std::string run_capture(const std::vector<std::string> & argv) {
    int pipefd[2];
    if (pipe(pipefd) != 0) {
        return "";
    }
    pid_t pid = fork();
    if (pid < 0) {
        close(pipefd[0]);
        close(pipefd[1]);
        return "";
    }
    if (pid == 0) {
        close(pipefd[0]);
        dup2(pipefd[1], STDOUT_FILENO);
        close(pipefd[1]);
        freopen("/dev/null", "w", stderr);
        std::vector<char *> args;
        args.reserve(argv.size() + 1);
        for (const auto & a : argv) {
            args.push_back(const_cast<char *>(a.c_str()));
        }
        args.push_back(nullptr);
        execvp(args[0], args.data());
        _exit(127);
    }
    close(pipefd[1]);
    std::string out;
    char buf[4096];
    ssize_t n;
    while ((n = read(pipefd[0], buf, sizeof(buf))) > 0) {
        out.append(buf, (size_t) n);
    }
    close(pipefd[0]);
    int status = 0;
    waitpid(pid, &status, 0);
    return out;
}

inline std::string trim(std::string s) {
    while (!s.empty() && std::isspace((unsigned char) s.front())) s.erase(s.begin());
    while (!s.empty() && std::isspace((unsigned char) s.back()))  s.pop_back();
    return s;
}

} // namespace detail

struct state {
    std::string card_name;
    std::string original_profile;
    bool        switched = false;
};

// Parses `pactl list cards` looking for the first card whose name starts
// with "bluez_card." and returns its name + currently active profile.
inline bool detect_bluetooth_card(state & st) {
    const std::string out = detail::run_capture({"pactl", "list", "cards"});
    if (out.empty()) {
        return false;
    }

    std::istringstream iss(out);
    std::string line;
    std::string current_card;

    while (std::getline(iss, line)) {
        const auto name_pos = line.find("Name: bluez_card.");
        if (name_pos != std::string::npos) {
            current_card = detail::trim(line.substr(name_pos + std::string("Name: ").size()));
            continue;
        }

        const auto profile_pos = line.find("Active Profile:");
        if (profile_pos != std::string::npos && !current_card.empty()) {
            st.card_name        = current_card;
            st.original_profile = detail::trim(line.substr(profile_pos + std::string("Active Profile:").size()));
            return true;
        }
    }

    return false;
}

// Switches the detected Bluetooth card to a handsfree profile so its
// microphone becomes available, remembering the original profile for
// restore(). No-op (returns without side effects) if there is no Bluetooth
// card, or if it's already on a handsfree profile.
inline void enable_mic_profile(state & st) {
    if (!detect_bluetooth_card(st)) {
        return;
    }

    if (st.original_profile == "headset-head-unit" ||
        st.original_profile == "headset-head-unit-cvsd") {
        return; // already mic-capable, nothing to switch/restore
    }

    fprintf(stderr, "%s: bluetooth headset detected (%s), switching profile '%s' -> 'headset-head-unit' for mic capture\n",
            __func__, st.card_name.c_str(), st.original_profile.c_str());

    if (detail::run({"pactl", "set-card-profile", st.card_name, "headset-head-unit"})) {
        st.switched = true;
        return;
    }

    fprintf(stderr, "%s: mSBC handsfree profile unavailable, falling back to CVSD (lower quality)\n", __func__);
    if (detail::run({"pactl", "set-card-profile", st.card_name, "headset-head-unit-cvsd"})) {
        st.switched = true;
    } else {
        fprintf(stderr, "%s: could not switch bluetooth profile, mic capture may fail or be silent\n", __func__);
    }
}

// Restores whatever profile was active before enable_mic_profile() ran.
// Safe to call multiple times (e.g. from both a signal handler and normal
// exit) and to call when enable_mic_profile() was never called / no-opped.
inline void restore(state & st) {
    if (!st.switched || st.card_name.empty()) {
        return;
    }
    detail::run({"pactl", "set-card-profile", st.card_name, st.original_profile});
    st.switched = false;
}

// RAII wrapper: switches the bluetooth mic profile on construction and
// restores it on destruction, so it happens on every return path out of
// main() (normal exit, early `return`, or Ctrl+C via SDL's SIGINT/SIGTERM
// handling) without needing a signal handler of our own. Pass `enabled =
// false` (e.g. from a --no-bt-fixup flag) to make it a no-op.
class mic_profile_guard {
public:
    explicit mic_profile_guard(bool enabled = true) {
        if (enabled) {
            enable_mic_profile(m_state);
        }
    }

    ~mic_profile_guard() {
        restore(m_state);
    }

    mic_profile_guard(const mic_profile_guard &)             = delete;
    mic_profile_guard & operator=(const mic_profile_guard &) = delete;

private:
    state m_state;
};

} // namespace bt_profile
