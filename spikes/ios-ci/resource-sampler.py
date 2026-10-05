#!/usr/bin/env python3
# Resource readings of the runner of an iOS job - NON-PRODUCTION / SYNTHETIC DATA ONLY.
# A hosted runner that is starved of memory, processor time or disk space is lost by its service, and a lost runner
# uploads nothing: neither the log of the job nor its evidence. Two things are kept here so that such a job still says
# where it was and in what state:
#
#   once                              prints one reading as a short line (the job script puts it into the note it
#                                     writes on the job page when a stage starts; notes survive a lost runner)
#   watch <file> <seconds> <job>      appends one reading per interval to <file> as a JSON line (uploaded with the
#                                     evidence when the job ends) and, the first time a reading crosses a limit, prints
#                                     one note for the job page with the processes that hold the most memory
#
# A reading: free memory (percent, as the system reports it), the memory pressure level of the kernel (1 normal,
# 2 warning, 4 critical), swap in use, free space of the volume of the working directory, the load average and the
# largest processes by resident memory and by processor share. A process is named by the file name of its command only:
# no path, no user name, no argument and no host name is read or kept.
import json
import os
import re
import subprocess
import sys
import time

MAX_NOTES = 3
LIMITS = (
    ('memory pressure critical', lambda r: r.get('pressure_level') is not None and r['pressure_level'] >= 4),
    ('free memory at or below 5 %', lambda r: r.get('memory_free_percent') is not None and r['memory_free_percent'] <= 5),
    ('swap in use at or above 3072 MiB', lambda r: r.get('swap_used_mib') is not None and r['swap_used_mib'] >= 3072),
    ('free disk space below 5 GiB', lambda r: r.get('disk_free_gib') is not None and r['disk_free_gib'] < 5),
    ('load average at or above four per processor', lambda r: r.get('load_1m') is not None and r.get('processors') and r['load_1m'] >= 4 * r['processors']),
)


def out(*argv):
    try:
        p = subprocess.run(list(argv), capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return None
    return p.stdout if p.returncode == 0 else None


def number(pattern, text, kind=float):
    m = re.search(pattern, text or '')
    try:
        return kind(m.group(1)) if m else None
    except ValueError:
        return None


def processes():
    rows = []
    for line in (out('ps', '-axo', 'pcpu=,rss=,comm=') or '').splitlines():
        parts = line.split(None, 2)
        if len(parts) != 3:
            continue
        try:
            rows.append({'name': os.path.basename(parts[2].strip())[:60], 'cpu_percent': float(parts[0]), 'rss_mib': round(int(parts[1]) / 1024)})
        except ValueError:
            continue
    by_memory = sorted(rows, key=lambda row: -row['rss_mib'])[:5]
    by_cpu = sorted(rows, key=lambda row: -row['cpu_percent'])[:3]
    return {'count': len(rows), 'by_memory': [{'name': r['name'], 'rss_mib': r['rss_mib']} for r in by_memory],
            'by_cpu': [{'name': r['name'], 'cpu_percent': r['cpu_percent']} for r in by_cpu]}


def reading(with_processes=True):
    record = {'at_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}
    record['memory_free_percent'] = number(r'System-wide memory free percentage:\s*(\d+)%', out('memory_pressure'), int)
    record['pressure_level'] = number(r'(\d+)', out('sysctl', '-n', 'kern.memorystatus_vm_pressure_level'), int)
    record['swap_used_mib'] = number(r'used = ([0-9.]+)M', out('sysctl', '-n', 'vm.swapusage'))
    try:
        volume = os.statvfs(os.getcwd())
        record['disk_free_gib'] = round(volume.f_bavail * volume.f_frsize / 2 ** 30, 1)
    except OSError:
        record['disk_free_gib'] = None
    try:
        record['load_1m'] = round(os.getloadavg()[0], 2)
    except OSError:
        record['load_1m'] = None
    record['processors'] = os.cpu_count()
    if with_processes:
        record['processes'] = processes()
    return record


def short(record):
    show = lambda value, unit='': 'unknown' if value is None else '%s%s' % (value, unit)
    return 'memory_free=%s pressure_level=%s swap_used=%s disk_free=%s load=%s' % (
        show(record.get('memory_free_percent'), '%'), show(record.get('pressure_level')), show(record.get('swap_used_mib'), 'MiB'),
        show(record.get('disk_free_gib'), 'GiB'), show(record.get('load_1m')))


def note(title, message):
    # a workflow command of the hosting service: the note is attached to the job page as soon as the line is read
    escape = lambda text: text.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
    print('::notice title=%s::%s' % (escape(title).replace(':', '%3A').replace(',', '%2C'), escape(message)), flush=True)


def watch(path, seconds, job):
    crossed, notes = set(), 0
    while True:
        record = reading()
        with open(path, 'a', encoding='utf-8') as file:
            file.write(json.dumps(record, sort_keys=True) + '\n')
        for name, test in LIMITS:
            if name in crossed or not test(record):
                continue
            crossed.add(name)
            if notes < MAX_NOTES:
                notes += 1
                largest = ', '.join('%s %s MiB' % (p['name'], p['rss_mib']) for p in record['processes']['by_memory'])
                note('g1 resource limit', '%s %s: %s; %s; largest processes: %s' % (job, record['at_utc'], name, short(record), largest))
        time.sleep(seconds)


def main(argv):
    if argv[1:2] == ['once']:
        print(short(reading(with_processes=False)))
        return 0
    if argv[1:2] == ['watch'] and len(argv) == 5:
        watch(argv[2], max(5, int(argv[3])), argv[4])
        return 0
    sys.stderr.write('usage: resource-sampler.py once | watch <file> <seconds> <job>\n')
    return 64


if __name__ == '__main__':
    sys.exit(main(sys.argv))
