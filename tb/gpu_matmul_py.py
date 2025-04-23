import numpy as np

# 生成两个矩阵
A = np.zeros([2, 4])  # 形状为(2, 8)的矩阵
B = np.zeros([3, 4])  # 形状为(3, 8)的矩阵

for i in range(A.shape[0]):
    for j in range(A.shape[1]):
        A[i][j] = i + j

for i in range(B.shape[0]):
    for j in range(B.shape[1]):
        B[i][j] = i + 2 + j
C = np.zeros((A.shape[0], B.shape[0]))
C = A @ B.T
print(A)
print(B)
print(C)

