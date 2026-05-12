import matplotlib.pyplot as plt
import numpy as np

stats = {}
with open('stats.csv', 'r') as file:
    # skip header (should probably check it ...)
    file.readline().strip()

    for line in file:
        data = line.strip().split(',')
        [name, opt_mode, time, r_len, a_len, b_len, op, value] = data
        time = float(time)
        r_len = int(r_len)
        value = int(value)

        if not name in stats:
            stats[name] = { 'ops': [op], 'values': [value], 'times': []}
        if op not in stats[name]['ops']:
            stats[name]['ops'].append(op)
        if value not in stats[name]['values']:
            stats[name]['values'].append(value)

        # currently, r_len = a_len = b_len
        stats[name]['times'].append((r_len, op, value, time))

fig, axs = plt.subplots(3, 3, layout='constrained', dpi=50)

merge_list = ['div1', 'carry']
show_label_list = ['div', 'carry', 'accum']
i = 0
for function, data in stats.items():
    ax = axs[i // 3][i % 3]

    if any([x in function for x in merge_list]):
        i -= 1

    show_op = len(data['ops']) > 1
    show_val = len(data['values']) > 1
    show_fn_label = any([x in function for x in show_label_list])
    for op in data['ops']:
        for value in data['values']:
            filtered = [entry for entry in data['times'] if entry[1] == op and entry[2] == value]

            X = np.array([entry[0] for entry in filtered])
            times = np.array([entry[3] for entry in filtered]) / 1000


            label = 'op=' + op if show_op else ''
            label += ', ' if show_val and show_op else ''
            if show_val and 'signed' in function:
                label += 'a_positive=' + str(value & 1 != 0) + ', b_positive=' + str(value & 0b10 != 0)
            else:
                label += 'value=' + str(value) if show_val else ''

            if show_fn_label:
                label = ', ' + label if len(label) else ''
                label = function + label
            ax.plot(X, times, label=label)

    ax.set_title(function)
    ax.set_xlabel('n limbs')
    ax.set_ylabel('Avg time (µs)')
    if show_op or show_val or show_fn_label:
        ax.legend(loc='best')
    i += 1

plt.show()
