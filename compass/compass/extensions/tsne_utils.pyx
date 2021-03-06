"""
New BSD License

Copyright (c) 20072017 The scikit-learn developers.
All rights reserved.


Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

  a. Redistributions of source code must retain the above copyright notice,
     this list of conditions and the following disclaimer.
  b. Redistributions in binary form must reproduce the above copyright
     notice, this list of conditions and the following disclaimer in the
     documentation and/or other materials provided with the distribution.
  c. Neither the name of the Scikit-learn Developers  nor the names of
     its contributors may be used to endorse or promote products
     derived from this software without specific prior written
     permission. 


THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
DAMAGE.
"""
from libc cimport math
cimport cython
import numpy as np
cimport numpy as np
from libc.stdio cimport printf
cdef extern from "numpy/npy_math.h":
    float NPY_INFINITY


cdef float EPSILON_DBL = 1e-8
cdef float PERPLEXITY_TOLERANCE = 1e-5

@cython.boundscheck(False)
cpdef np.ndarray[np.float32_t, ndim=2] binary_search_perplexity(
        np.ndarray[np.float32_t, ndim=2] affinities, 
        np.ndarray[np.int64_t, ndim=2] neighbors, 
        float desired_perplexity,
        int verbose):
    """Binary search for sigmas of conditional Gaussians. 
    
    This approximation reduces the computational complexity from O(N^2) to
    O(uN). See the exact method '_binary_search_perplexity' for more details.

    Parameters
    ----------
    affinities : array-like, shape (n_samples, n_samples)
        Distances between training samples.

    neighbors : array-like, shape (n_samples, K) or None
        Each row contains the indices to the K nearest neigbors. If this
        array is None, then the perplexity is estimated over all data
        not just the nearest neighbors.

    desired_perplexity : float
        Desired perplexity (2^entropy) of the conditional Gaussians.

    verbose : int
        Verbosity level.

    Returns
    -------
    P : array, shape (n_samples, n_samples)
        Probabilities of conditional Gaussian distributions p_i|j.
    """
    # Maximum number of binary search steps
    cdef long n_steps = 100

    cdef long n_samples = affinities.shape[0]
    # This array is later used as a 32bit array. It has multiple intermediate
    # floating point additions that benefit from the extra precision
    cdef np.ndarray[np.float64_t, ndim=2] P = np.zeros((n_samples, n_samples),
                                                       dtype=np.float64)
    # Precisions of conditional Gaussian distrubutions
    cdef float beta
    cdef float beta_min
    cdef float beta_max
    cdef float beta_sum = 0.0
    # Now we go to log scale
    cdef float desired_entropy = math.log(desired_perplexity)
    cdef float entropy_diff

    cdef float entropy
    cdef float sum_Pi
    cdef float sum_disti_Pi
    cdef long i, j, k, l = 0
    cdef long K = n_samples
    cdef int using_neighbors = neighbors is not None

    if using_neighbors:
        K = neighbors.shape[1]

    for i in range(n_samples):
        beta_min = -NPY_INFINITY
        beta_max = NPY_INFINITY
        beta = 1.0

        # Binary search of precision for i-th conditional distribution
        for l in range(n_steps):
            # Compute current entropy and corresponding probabilities
            # computed just over the nearest neighbors or over all data
            # if we're not using neighbors
            if using_neighbors:
                for k in range(K):
                    j = neighbors[i, k]
                    P[i, j] = math.exp(-affinities[i, j] * beta)
            else:
                for j in range(K):
                    P[i, j] = math.exp(-affinities[i, j] * beta)
            P[i, i] = 0.0
            sum_Pi = 0.0
            if using_neighbors:
                for k in range(K):
                    j = neighbors[i, k]
                    sum_Pi += P[i, j]
            else:
                for j in range(K):
                    sum_Pi += P[i, j]
            if sum_Pi == 0.0:
                sum_Pi = EPSILON_DBL
            sum_disti_Pi = 0.0
            if using_neighbors:
                for k in range(K):
                    j = neighbors[i, k]
                    P[i, j] /= sum_Pi
                    sum_disti_Pi += affinities[i, j] * P[i, j]
            else:
                for j in range(K):
                    P[i, j] /= sum_Pi
                    sum_disti_Pi += affinities[i, j] * P[i, j]
            entropy = math.log(sum_Pi) + beta * sum_disti_Pi
            entropy_diff = entropy - desired_entropy

            if math.fabs(entropy_diff) <= PERPLEXITY_TOLERANCE:
                break

            if entropy_diff > 0.0:
                beta_min = beta
                if beta_max == NPY_INFINITY:
                    beta *= 2.0
                else:
                    beta = (beta + beta_max) / 2.0
            else:
                beta_max = beta
                if beta_min == -NPY_INFINITY:
                    beta /= 2.0
                else:
                    beta = (beta + beta_min) / 2.0

        beta_sum += beta

        if verbose and ((i + 1) % 1000 == 0 or i + 1 == n_samples):
            print("[t-SNE] Computed conditional probabilities for sample "
                  "%d / %d" % (i + 1, n_samples))

    if verbose:
        print("[t-SNE] Mean sigma: %f"
              % np.mean(math.sqrt(n_samples / beta_sum)))
    return P


@cython.boundscheck(False)
cpdef np.ndarray[np.float32_t, ndim=1] binary_search_perplexity_single(
        np.ndarray[np.float32_t, ndim=1] affinities, 
        np.ndarray[np.int64_t, ndim=1] neighbors, 
        float desired_perplexity,
        int verbose, int sample):
    """Binary search for sigmas of conditional Gaussians. 
    
    This approximation reduces the computational complexity from O(N^2) to
    O(uN). See the exact method '_binary_search_perplexity' for more details.

    This version only computes the p-values for a single sample

    Parameters
    ----------
    affinities : array-like, shape (n_samples, n_samples)
        Distances between training samples.

    neighbors : array-like, shape (n_samples, K) or None
        Each row contains the indices to the K nearest neigbors. If this
        array is None, then the perplexity is estimated over all data
        not just the nearest neighbors.

    desired_perplexity : float
        Desired perplexity (2^entropy) of the conditional Gaussians.

    verbose : int
        Verbosity level.

    Returns
    -------
    P : array, shape (n_samples, n_samples)
        Probabilities of conditional Gaussian distributions p_i|j.
    """
    # Maximum number of binary search steps
    cdef long n_steps = 100

    cdef long n_samples = affinities.shape[0]
    # This array is later used as a 32bit array. It has multiple intermediate
    # floating point additions that benefit from the extra precision
    cdef np.ndarray[np.float64_t, ndim=1] P = np.zeros(n_samples, dtype=np.float64)
    # Precisions of conditional Gaussian distrubutions
    cdef float beta
    cdef float beta_min
    cdef float beta_max
    # Now we go to log scale
    cdef float desired_entropy = math.log(desired_perplexity)
    cdef float entropy_diff

    cdef float entropy
    cdef float sum_Pi
    cdef float sum_disti_Pi
    cdef long i, j, k, l = 0
    cdef long K = n_samples
    cdef int using_neighbors = neighbors is not None

    if using_neighbors:
        K = neighbors.shape[0]

    i = 0
    cdef long sample_i = sample

    beta_min = -NPY_INFINITY
    beta_max = NPY_INFINITY
    beta = 1.0

    # Binary search of precision for i-th conditional distribution
    for l in range(n_steps):
        # Compute current entropy and corresponding probabilities
        # computed just over the nearest neighbors or over all data
        # if we're not using neighbors
        if using_neighbors:
            for k in range(K):
                j = neighbors[k]
                P[j] = math.exp(-affinities[j] * beta)
        else:
            for j in range(K):
                P[j] = math.exp(-affinities[j] * beta)

        P[sample_i] = 0.0
        sum_Pi = 0.0

        if using_neighbors:
            for k in range(K):
                j = neighbors[k]
                sum_Pi += P[j]
        else:
            for j in range(K):
                sum_Pi += P[j]
        if sum_Pi == 0.0:
            sum_Pi = EPSILON_DBL
        sum_disti_Pi = 0.0

        if using_neighbors:
            for k in range(K):
                j = neighbors[k]
                P[j] /= sum_Pi
                sum_disti_Pi += affinities[j] * P[j]
        else:
            for j in range(K):
                P[j] /= sum_Pi
                sum_disti_Pi += affinities[j] * P[j]

        entropy = math.log(sum_Pi) + beta * sum_disti_Pi
        entropy_diff = entropy - desired_entropy

        if math.fabs(entropy_diff) <= PERPLEXITY_TOLERANCE:
            break

        if entropy_diff > 0.0:
            beta_min = beta
            if beta_max == NPY_INFINITY:
                beta *= 2.0
            else:
                beta = (beta + beta_max) / 2.0
        else:
            beta_max = beta
            if beta_min == -NPY_INFINITY:
                beta /= 2.0
            else:
                beta = (beta + beta_min) / 2.0

    if verbose:
        print("[t-SNE] Sigma: %f" % math.sqrt(1 / beta))

    return P
