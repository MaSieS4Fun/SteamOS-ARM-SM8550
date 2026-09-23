#include "mini/image.hpp"
#include "common/exception.hpp"
#include "layer.hpp"

#include <vulkan/vulkan_core.h>

#include <memory>
#include <cstdint>
#include <optional>

using namespace Mini;

Image::Image(VkDevice device, VkPhysicalDevice physicalDevice,
        VkExtent2D extent, VkFormat format,
        VkImageUsageFlags usage, VkImageAspectFlags aspectFlags, int* fd)
        : extent(extent), format(format), aspectFlags(aspectFlags) {
    // create image
    const VkExternalMemoryImageCreateInfo externalInfo{
        .sType = VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO,
        .handleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_FD_BIT_KHR
    };
    const VkImageCreateInfo desc{
        .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .pNext = &externalInfo,
        .imageType = VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = {
            .width = extent.width,
            .height = extent.height,
            .depth = 1
        },
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = VK_SAMPLE_COUNT_1_BIT,
        .usage = usage,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE
    };
    VkImage imageHandle{};
    auto res = Layer::ovkCreateImage(device, &desc, nullptr, &imageHandle);
    if (res != VK_SUCCESS || imageHandle == VK_NULL_HANDLE)
        throw LSFG::vulkan_error(res, "Failed to create Vulkan image");

    // find memory type
    VkPhysicalDeviceMemoryProperties memProps;
    Layer::ovkGetPhysicalDeviceMemoryProperties(physicalDevice, &memProps);

    VkMemoryRequirements memReqs;
    Layer::ovkGetImageMemoryRequirements(device, imageHandle, &memReqs);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunsafe-buffer-usage"
    std::optional<uint32_t> memType{};
    for (uint32_t i = 0; i < memProps.memoryTypeCount; ++i) {
        if ((memReqs.memoryTypeBits & (1 << i)) && // NOLINTBEGIN
            (memProps.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)) {
            memType.emplace(i);
            break;
        } // NOLINTEND
    }
    if (!memType.has_value())
        throw LSFG::vulkan_error(VK_ERROR_UNKNOWN, "Unable to find memory type for image");
#pragma clang diagnostic pop

    // allocate and bind memory
    const VkMemoryDedicatedAllocateInfoKHR dedicatedInfo{
        .sType = VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO_KHR,
        .image = imageHandle,
    };
    const VkExportMemoryAllocateInfo exportInfo{
        .sType = VK_STRUCTURE_TYPE_EXPORT_MEMORY_ALLOCATE_INFO,
        .pNext = &dedicatedInfo,
        .handleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_FD_BIT_KHR
    };
    const VkMemoryAllocateInfo allocInfo{
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .pNext = &exportInfo,
        .allocationSize = memReqs.size,
        .memoryTypeIndex = memType.value()
    };
    VkDeviceMemory memoryHandle{};
    res = Layer::ovkAllocateMemory(device, &allocInfo, nullptr, &memoryHandle);
    if (res != VK_SUCCESS || memoryHandle == VK_NULL_HANDLE)
        throw LSFG::vulkan_error(res, "Failed to allocate memory for Vulkan image");

    res = Layer::ovkBindImageMemory(device, imageHandle, memoryHandle, 0);
    if (res != VK_SUCCESS)
        throw LSFG::vulkan_error(res, "Failed to bind memory to Vulkan image");

    // obtain the sharing fd
    const VkMemoryGetFdInfoKHR fdInfo{
        .sType = VK_STRUCTURE_TYPE_MEMORY_GET_FD_INFO_KHR,
        .memory = memoryHandle,
        .handleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_FD_BIT_KHR,
    };
    res = Layer::ovkGetMemoryFdKHR(device, &fdInfo, fd);
    if (res != VK_SUCCESS || *fd < 0)
        throw LSFG::vulkan_error(res, "Failed to obtain sharing fd for Vulkan image");

    // store objects in shared ptr
    this->image = std::shared_ptr<VkImage>(
        new VkImage(imageHandle),
        [dev = device](VkImage* img) {
            Layer::ovkDestroyImage(dev, *img, nullptr);
        }
    );
    this->memory = std::shared_ptr<VkDeviceMemory>(
        new VkDeviceMemory(memoryHandle),
        [dev = device](VkDeviceMemory* mem) {
            Layer::ovkFreeMemory(dev, *mem, nullptr);
        }
    );
}
