tb_dir = 'tb0_data'
channels = 4
ofmap_col = 3
kernels = 16

with open(f'{tb_dir}/ifmap0.txt') as f:
    A = [int(i) for i in f.readlines()]

with open(f'{tb_dir}/filter.txt') as f:
    B = [int(i) for i in f.readlines()]

with open(f'{tb_dir}/ipsum0.txt') as f:
    C = [int(i) for i in f.readlines()]

with open(f'{tb_dir}/golden.txt') as f:
    D = [int(i) for i in f.readlines()]

print(f'             {" ":6s}{"mac":10s} {"ipsum":10s}   {"res":10s}')
print('--------------------------------------------------')
for k in range(kernels):
    for col in range(ofmap_col):
        bb = k*channels*3
        aa = 0 + col*4
        cc = k*ofmap_col + col
        mac = sum([a * b for a, b in zip(A[aa:aa+3*channels], B[bb:bb+3*channels])])
        ipsum = C[cc]
        gold = D[cc]
        print(f'{aa:3d} {bb:4d} {cc:3d} {mac:10d} + {ipsum:10d} = {gold:8d}')
    print('--------------------------------------------------')
