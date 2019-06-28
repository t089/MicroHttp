//
//  getCPU.h
//  Cmetrics
//
//  Created by Tobias Haeberle on 14.02.19.
//

#ifndef getCPU_h
#define getCPU_h

#include "stdlib.h"
#include "stdio.h"
#include "string.h"

#if defined(__unix__) || defined(__unix) || defined(unix) || (defined(__APPLE__) && defined(__MACH__))
#include <unistd.h>
#include <sys/resource.h>
#endif

typedef struct {
#if defined(__linux__) || defined(__linux) || defined(linux) || defined(__gnu_linux__)
    clock_t lastCPU, lastSysCPU, lastUserCPU;
#endif
    int numProcessors;
} metrics_cpu_info ;

metrics_cpu_info * cpu_info_new();
void cpu_info_free(metrics_cpu_info *info);
void cpu_info_init(metrics_cpu_info *info);
double cpu_info_get_current_usage(metrics_cpu_info *info);


#endif /* getCPU_h */
