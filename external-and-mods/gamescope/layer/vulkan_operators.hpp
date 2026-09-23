#pragma once

#include <vulkan/vulkan_core.h>

inline bool operator == (
  const VkImageSubresourceRange& a,
  const VkImageSubresourceRange& b) {
  return a.aspectMask     == b.aspectMask
      && a.baseMipLevel   == b.baseMipLevel
      && a.levelCount     == b.levelCount
      && a.baseArrayLayer == b.baseArrayLayer
      && a.layerCount     == b.layerCount;
}


inline bool operator != (
  const VkImageSubresourceRange& a,
  const VkImageSubresourceRange& b) {
  return !operator == (a, b);
}


inline bool operator == (
  const VkImageSubresourceLayers& a,
  const VkImageSubresourceLayers& b) {
  return a.aspectMask     == b.aspectMask
      && a.mipLevel       == b.mipLevel
      && a.baseArrayLayer == b.baseArrayLayer
      && a.layerCount     == b.layerCount;
}


inline bool operator != (
  const VkImageSubresourceLayers& a,
  const VkImageSubresourceLayers& b) {
  return !operator == (a, b);
}


inline bool operator == (VkExtent3D a, VkExtent3D b) {
  return a.width  == b.width
      && a.height == b.height
      && a.depth  == b.depth;
}


inline bool operator != (VkExtent3D a, VkExtent3D b) {
  return a.width  != b.width
      || a.height != b.height
      || a.depth  != b.depth;
}


inline bool operator == (VkExtent2D a, VkExtent2D b) {
  return a.width  == b.width
      && a.height == b.height;
}


inline bool operator != (VkExtent2D a, VkExtent2D b) {
  return a.width  != b.width
      || a.height != b.height;
}


inline bool operator == (VkOffset3D a, VkOffset3D b) {
  return a.x == b.x
      && a.y == b.y
      && a.z == b.z;
}


inline bool operator != (VkOffset3D a, VkOffset3D b) {
  return a.x != b.x
      || a.y != b.y
      || a.z != b.z;
}


inline bool operator == (VkOffset2D a, VkOffset2D b) {
  return a.x == b.x
      && a.y == b.y;
}


inline bool operator != (VkOffset2D a, VkOffset2D b) {
  return a.x != b.x
      || a.y != b.y;
}

