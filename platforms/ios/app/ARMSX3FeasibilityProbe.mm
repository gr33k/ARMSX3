#import "ARMSX3FeasibilityProbe.h"

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>

#include <MoltenVK/vk_mvk_moltenvk.h>
#include <libkern/OSCacheControl.h>
#include <pthread.h>
#include <sys/mman.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <cstring>
#include <string>
#include <vector>

namespace
{
void emit(ARMSX3ProbeUpdate update, NSString* line)
{
    NSLog(@"[ARMSX3 iOS] %@", line);
    if (update)
        update(line);
}

bool run_jit_probe(ARMSX3ProbeUpdate update)
{
    emit(update, @"[JIT] Allocating one MAP_JIT page...");

    const size_t page_size = static_cast<size_t>(getpagesize());
    void* memory = mmap(nullptr, page_size, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
    if (memory == MAP_FAILED)
    {
        emit(update, [NSString stringWithFormat:@"[JIT] FAIL: mmap errno=%d (%s)", errno, strerror(errno)]);
        return false;
    }

    // mov w0, #42; ret
    constexpr uint32_t program[] = {0x52800540u, 0xd65f03c0u};
    memcpy(memory, program, sizeof(program));
    sys_icache_invalidate(memory, sizeof(program));
    if (mprotect(memory, page_size, PROT_READ | PROT_EXEC) != 0)
    {
        emit(update, [NSString stringWithFormat:@"[JIT] FAIL: mprotect RX errno=%d (%s)", errno, strerror(errno)]);
        munmap(memory, page_size);
        return false;
    }

    using probe_fn = int (*)();
    const int result = reinterpret_cast<probe_fn>(memory)();
    munmap(memory, page_size);

    if (result != 42)
    {
        emit(update, [NSString stringWithFormat:@"[JIT] FAIL: generated code returned %d", result]);
        return false;
    }

    emit(update, @"[JIT] PASS: generated AArch64 code returned 42");
    return true;
}

bool has_extension(const std::vector<VkExtensionProperties>& extensions, const char* name)
{
    return std::any_of(extensions.begin(), extensions.end(), [name](const VkExtensionProperties& extension) {
        return strcmp(extension.extensionName, name) == 0;
    });
}

bool run_vulkan_probe(ARMSX3ProbeUpdate update)
{
    id<MTLDevice> metal_device = MTLCreateSystemDefaultDevice();
    if (!metal_device)
    {
        emit(update, @"[Metal] FAIL: MTLCreateSystemDefaultDevice returned nil");
        return false;
    }
    emit(update, [NSString stringWithFormat:@"[Metal] Device: %@", metal_device.name]);

    uint32_t instance_extension_count = 0;
    if (vkEnumerateInstanceExtensionProperties(nullptr, &instance_extension_count, nullptr) != VK_SUCCESS)
    {
        emit(update, @"[Vulkan] FAIL: cannot enumerate instance extensions");
        return false;
    }

    std::vector<VkExtensionProperties> instance_extensions(instance_extension_count);
    if (vkEnumerateInstanceExtensionProperties(nullptr, &instance_extension_count, instance_extensions.data()) != VK_SUCCESS)
    {
        emit(update, @"[Vulkan] FAIL: cannot read instance extensions");
        return false;
    }

    const char* required_instance_extensions[] = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_EXT_METAL_SURFACE_EXTENSION_NAME,
        VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME,
    };
    for (const char* extension : required_instance_extensions)
    {
        if (!has_extension(instance_extensions, extension))
        {
            emit(update, [NSString stringWithFormat:@"[Vulkan] FAIL: missing %s", extension]);
            return false;
        }
    }

    VkApplicationInfo application_info{VK_STRUCTURE_TYPE_APPLICATION_INFO};
    application_info.pApplicationName = "ARMSX3 iOS Feasibility";
    application_info.applicationVersion = VK_MAKE_API_VERSION(0, 0, 1, 0);
    application_info.pEngineName = "ARMSX3";
    application_info.engineVersion = VK_MAKE_API_VERSION(0, 0, 1, 0);
    application_info.apiVersion = VK_API_VERSION_1_2;

    VkInstanceCreateInfo instance_info{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    instance_info.flags = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    instance_info.pApplicationInfo = &application_info;
    instance_info.enabledExtensionCount = static_cast<uint32_t>(std::size(required_instance_extensions));
    instance_info.ppEnabledExtensionNames = required_instance_extensions;

    VkInstance instance = VK_NULL_HANDLE;
    VkResult result = vkCreateInstance(&instance_info, nullptr, &instance);
    if (result != VK_SUCCESS)
    {
        emit(update, [NSString stringWithFormat:@"[Vulkan] FAIL: vkCreateInstance=%d", result]);
        return false;
    }

    CAMetalLayer* metal_layer = [CAMetalLayer layer];
    metal_layer.device = metal_device;
    metal_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    metal_layer.drawableSize = CGSizeMake(64.0, 64.0);

    VkMetalSurfaceCreateInfoEXT surface_info{VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT};
    surface_info.pLayer = metal_layer;
    VkSurfaceKHR surface = VK_NULL_HANDLE;
    result = vkCreateMetalSurfaceEXT(instance, &surface_info, nullptr, &surface);
    if (result != VK_SUCCESS)
    {
        emit(update, [NSString stringWithFormat:@"[Vulkan] FAIL: vkCreateMetalSurfaceEXT=%d", result]);
        vkDestroyInstance(instance, nullptr);
        return false;
    }

    uint32_t physical_device_count = 0;
    result = vkEnumeratePhysicalDevices(instance, &physical_device_count, nullptr);
    if (result != VK_SUCCESS || physical_device_count == 0)
    {
        emit(update, [NSString stringWithFormat:@"[Vulkan] FAIL: physical devices=%u result=%d", physical_device_count, result]);
        vkDestroySurfaceKHR(instance, surface, nullptr);
        vkDestroyInstance(instance, nullptr);
        return false;
    }

    std::vector<VkPhysicalDevice> physical_devices(physical_device_count);
    vkEnumeratePhysicalDevices(instance, &physical_device_count, physical_devices.data());
    VkPhysicalDevice physical_device = physical_devices.front();

    VkPhysicalDeviceProperties properties{};
    vkGetPhysicalDeviceProperties(physical_device, &properties);
    emit(update, [NSString stringWithFormat:@"[Vulkan] Device: %s", properties.deviceName]);
    emit(update, [NSString stringWithFormat:@"[Vulkan] API: %u.%u.%u driver=%u",
        VK_API_VERSION_MAJOR(properties.apiVersion),
        VK_API_VERSION_MINOR(properties.apiVersion),
        VK_API_VERSION_PATCH(properties.apiVersion),
        properties.driverVersion]);

    VkPhysicalDeviceMemoryProperties memory_properties{};
    vkGetPhysicalDeviceMemoryProperties(physical_device, &memory_properties);
    VkDeviceSize device_local_bytes = 0;
    for (uint32_t index = 0; index < memory_properties.memoryHeapCount; ++index)
    {
        if (memory_properties.memoryHeaps[index].flags & VK_MEMORY_HEAP_DEVICE_LOCAL_BIT)
            device_local_bytes += memory_properties.memoryHeaps[index].size;
    }
    emit(update, [NSString stringWithFormat:@"[Vulkan] Device-local heap: %.2f GiB",
        static_cast<double>(device_local_bytes) / (1024.0 * 1024.0 * 1024.0)]);

    uint32_t queue_family_count = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, nullptr);
    std::vector<VkQueueFamilyProperties> queue_families(queue_family_count);
    vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, queue_families.data());

    uint32_t queue_family = UINT32_MAX;
    for (uint32_t index = 0; index < queue_family_count; ++index)
    {
        VkBool32 presents = VK_FALSE;
        vkGetPhysicalDeviceSurfaceSupportKHR(physical_device, index, surface, &presents);
        if ((queue_families[index].queueFlags & VK_QUEUE_GRAPHICS_BIT) && presents)
        {
            queue_family = index;
            break;
        }
    }
    if (queue_family == UINT32_MAX)
    {
        emit(update, @"[Vulkan] FAIL: no graphics/present queue");
        vkDestroySurfaceKHR(instance, surface, nullptr);
        vkDestroyInstance(instance, nullptr);
        return false;
    }

    uint32_t device_extension_count = 0;
    vkEnumerateDeviceExtensionProperties(physical_device, nullptr, &device_extension_count, nullptr);
    std::vector<VkExtensionProperties> device_extensions(device_extension_count);
    vkEnumerateDeviceExtensionProperties(physical_device, nullptr, &device_extension_count, device_extensions.data());

    std::vector<const char*> enabled_device_extensions;
    if (has_extension(device_extensions, VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME))
        enabled_device_extensions.push_back(VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME);

    const float queue_priority = 1.0f;
    VkDeviceQueueCreateInfo queue_info{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    queue_info.queueFamilyIndex = queue_family;
    queue_info.queueCount = 1;
    queue_info.pQueuePriorities = &queue_priority;

    VkDeviceCreateInfo device_info{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    device_info.queueCreateInfoCount = 1;
    device_info.pQueueCreateInfos = &queue_info;
    device_info.enabledExtensionCount = static_cast<uint32_t>(enabled_device_extensions.size());
    device_info.ppEnabledExtensionNames = enabled_device_extensions.data();

    VkDevice device = VK_NULL_HANDLE;
    result = vkCreateDevice(physical_device, &device_info, nullptr, &device);
    if (result != VK_SUCCESS)
    {
        emit(update, [NSString stringWithFormat:@"[Vulkan] FAIL: vkCreateDevice=%d", result]);
        vkDestroySurfaceKHR(instance, surface, nullptr);
        vkDestroyInstance(instance, nullptr);
        return false;
    }

    VkSurfaceCapabilitiesKHR capabilities{};
    result = vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &capabilities);
    if (result != VK_SUCCESS)
    {
        emit(update, [NSString stringWithFormat:@"[Vulkan] FAIL: surface capabilities=%d", result]);
        vkDestroyDevice(device, nullptr);
        vkDestroySurfaceKHR(instance, surface, nullptr);
        vkDestroyInstance(instance, nullptr);
        return false;
    }

    emit(update, [NSString stringWithFormat:@"[Vulkan] Metal surface extent: %ux%u",
        capabilities.currentExtent.width, capabilities.currentExtent.height]);
    emit(update, @"[Vulkan] PASS: instance, Metal surface, GPU, queue, and logical device");

    vkDestroyDevice(device, nullptr);
    vkDestroySurfaceKHR(instance, surface, nullptr);
    vkDestroyInstance(instance, nullptr);
    return true;
}
} // namespace

@implementation ARMSX3FeasibilityProbe

+ (void)runWithUpdate:(ARMSX3ProbeUpdate)update completion:(ARMSX3ProbeCompletion)completion
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        emit(update, [NSString stringWithFormat:@"Device: %@ / iOS %@",
            UIDevice.currentDevice.model, UIDevice.currentDevice.systemVersion]);
        const bool jit_passed = run_jit_probe(update);
        const bool vulkan_passed = run_vulkan_probe(update);
        const bool passed = jit_passed && vulkan_passed;
        emit(update, passed ? @"OVERALL PASS" : @"OVERALL FAIL");
        if (completion)
            completion(passed);
    });
}

@end
