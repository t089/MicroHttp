//
//  getCPU.c
//  Cmetrics
//
//  Created by Tobias Haeberle on 14.02.19.
//

#include "getCPU.h"

#include "stdlib.h"
#include "stdio.h"
#include "string.h"

#if defined(__linux__) || defined(__linux) || defined(linux) || defined(__gnu_linux__)
#include "sys/times.h"
#include "sys/vtimes.h"
#else

#import <mach/mach.h>
#import <sys/resource.h>
#import <assert.h>

#endif


metrics_cpu_info * cpu_info_new() {
    metrics_cpu_info * info = (metrics_cpu_info *)malloc(sizeof(metrics_cpu_info));
    info->numProcessors = 0;
    return info;
}

void cpu_info_free(metrics_cpu_info *info) {
    free(info);
}


#if defined(__linux__) || defined(__linux) || defined(linux) || defined(__gnu_linux__)



void cpu_info_init(metrics_cpu_info *info) {
    FILE* file;
    struct tms timeSample;
    char line[128];
    
    info->lastCPU = times(&timeSample);
    info->lastSysCPU = timeSample.tms_stime;
    info->lastUserCPU = timeSample.tms_utime;
    
    file = fopen("/proc/cpuinfo", "r");
    info->numProcessors = 0;
    while(fgets(line, 128, file) != NULL){
        if (strncmp(line, "processor", 9) == 0) info->numProcessors++;
    }
    fclose(file);
}

double cpu_info_get_current_usage(metrics_cpu_info *info) {
    struct tms timeSample;
    clock_t now;
    double ratio;
    
    clock_t lastCPU;
    clock_t lastSysCPU;
    clock_t lastUserCPU;
    int numProcessors;
    
    lastCPU = info->lastCPU;
    lastSysCPU = info->lastSysCPU;
    lastUserCPU = info->lastUserCPU;
    numProcessors = info->numProcessors;
    
    now = times(&timeSample);
    if (now <= lastCPU || timeSample.tms_stime < lastSysCPU ||
        timeSample.tms_utime < lastUserCPU){
        //Overflow detection. Just skip this value.
        ratio = -1.0;
    } else {
        ratio = (timeSample.tms_stime - lastSysCPU) +
        (timeSample.tms_utime - lastUserCPU);
        ratio /= (now - lastCPU);
        //ratio /= numProcessors;
        //ratio *= 100;
    }
    
    info->lastCPU = now;
    info->lastSysCPU = timeSample.tms_stime;
    info->lastUserCPU = timeSample.tms_utime;
    
    return ratio;
}
#else



void cpu_info_init(metrics_cpu_info *info) {
    // noop
}

double cpu_info_get_current_usage(metrics_cpu_info *info) {
    kern_return_t kr;
    task_info_data_t tinfo;
    mach_msg_type_number_t task_info_count;
    
    task_info_count = TASK_INFO_MAX;
    kr = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)tinfo, &task_info_count);
    if (kr != KERN_SUCCESS) {
        return -1;
    }
    
    task_basic_info_t      basic_info;
    thread_array_t         thread_list;
    mach_msg_type_number_t thread_count;
    
    thread_info_data_t     thinfo;
    mach_msg_type_number_t thread_info_count;
    
    thread_basic_info_t basic_info_th;
    uint32_t stat_thread = 0; // Mach threads
    
    basic_info = (task_basic_info_t)tinfo;
    
    // get threads in the task
    kr = task_threads(mach_task_self(), &thread_list, &thread_count);
    if (kr != KERN_SUCCESS) {
        return -1;
    }
    if (thread_count > 0)
        stat_thread += thread_count;
    
    long tot_sec = 0;
    long tot_usec = 0;
    double tot_cpu = 0;
    int j;
    
    for (j = 0; j < (int)thread_count; j++)
    {
        thread_info_count = THREAD_INFO_MAX;
        kr = thread_info(thread_list[j], THREAD_BASIC_INFO,
                         (thread_info_t)thinfo, &thread_info_count);
        if (kr != KERN_SUCCESS) {
            return -1;
        }
        
        basic_info_th = (thread_basic_info_t)thinfo;
        
        if (!(basic_info_th->flags & TH_FLAGS_IDLE)) {
            tot_sec = tot_sec + basic_info_th->user_time.seconds + basic_info_th->system_time.seconds;
            tot_usec = tot_usec + basic_info_th->user_time.microseconds + basic_info_th->system_time.microseconds;
            tot_cpu = tot_cpu + basic_info_th->cpu_usage  / (float)TH_USAGE_SCALE /* * 100.0 */;
        }
        
    } // for each thread
    
    kr = vm_deallocate(mach_task_self(), (vm_offset_t)thread_list, thread_count * sizeof(thread_t));
    assert(kr == KERN_SUCCESS);
    
    return tot_cpu;
}
#endif
