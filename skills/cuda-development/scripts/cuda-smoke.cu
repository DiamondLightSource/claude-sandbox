// Smoke test for the CUDA toolkit and GPU access: list the devices, then add
// two vectors on device 0 and check every element on the host.
#include <cmath>
#include <cstdio>
#include <vector>

#define CHECK(call)                                                         \
    do {                                                                    \
        cudaError_t err = (call);                                           \
        if (err != cudaSuccess) {                                           \
            std::fprintf(stderr, "%s failed: %s (%s)\n", #call,             \
                         cudaGetErrorName(err), cudaGetErrorString(err));   \
            return 1;                                                       \
        }                                                                   \
    } while (0)

__global__ void vadd(const float *a, const float *b, float *c, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) c[i] = a[i] + b[i];
}

int main() {
    int driver = 0, runtime = 0, count = 0;
    CHECK(cudaDriverGetVersion(&driver));
    CHECK(cudaRuntimeGetVersion(&runtime));
    CHECK(cudaGetDeviceCount(&count));
    std::printf("CUDA driver %d.%d, runtime %d.%d, %d device(s)\n",
                driver / 1000, driver % 1000 / 10,
                runtime / 1000, runtime % 1000 / 10, count);
    for (int d = 0; d < count; ++d) {
        cudaDeviceProp p;
        CHECK(cudaGetDeviceProperties(&p, d));
        std::printf("  %d: %s, sm_%d%d, %.1f GiB\n", d, p.name, p.major,
                    p.minor, p.totalGlobalMem / 1073741824.0);
    }

    const int n = 1 << 24;
    const size_t bytes = n * sizeof(float);
    std::vector<float> a(n), b(n), c(n);
    for (int i = 0; i < n; ++i) {
        a[i] = i * 0.5f;
        b[i] = 1000.0f - i * 0.25f;
    }
    float *da, *db, *dc;
    CHECK(cudaMalloc(&da, bytes));
    CHECK(cudaMalloc(&db, bytes));
    CHECK(cudaMalloc(&dc, bytes));
    CHECK(cudaMemcpy(da, a.data(), bytes, cudaMemcpyHostToDevice));
    CHECK(cudaMemcpy(db, b.data(), bytes, cudaMemcpyHostToDevice));
    vadd<<<(n + 255) / 256, 256>>>(da, db, dc, n);
    CHECK(cudaGetLastError());
    CHECK(cudaMemcpy(c.data(), dc, bytes, cudaMemcpyDeviceToHost));
    CHECK(cudaFree(da));
    CHECK(cudaFree(db));
    CHECK(cudaFree(dc));

    int bad = 0;
    for (int i = 0; i < n; ++i) {
        float want = a[i] + b[i];
        if (std::fabs(c[i] - want) > 1e-3f * std::fabs(want) + 1e-3f) ++bad;
    }
    std::printf("vadd of %d floats on device 0: %d mismatches: %s\n", n, bad,
                bad ? "FAIL" : "PASS");
    return bad != 0;
}
