# def selection_sort(arr):
#     for i in range(len(arr)):
#         min_idx = i
#         print(f"Min index {min_idx}")
#         for j in range(i + 1, len(arr)):
#             print(f"j {j}")
#             if arr[j] < arr[min_idx]:
#                 min_idx = j
            
#         print(f"Array Min index {arr[min_idx]}")
#         print(f"Array i {arr[i]}")
#         arr[i], arr[min_idx] = arr[min_idx], arr[i]
        
#         print(f"Array Min index {arr[min_idx]}")
#         print(f"Array i {arr[i]}")
#     return arr

# print(selection_sort([64, 25, 12, 22, 11, 90, 1, 5, 6]))



# def countdown(i):
#     if i <= 0:           # Cas de base
#         return
#     else:                # Cas récursif
#         print(i)
#         countdown(i - 1)

# print(countdown(50))


def factorial(n):
    if n == 1:           # Cas de base
        print("Cas de base")
        return 1
    else:                # Cas récursif
        print("Cas récursif")
        return n * factorial(n - 1)

print(factorial(5))