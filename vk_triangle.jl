using VulkanCore
using GLFW

WIDTH = 640
HEIGHT = 480
window = GLFW.Window
instance = Ref{vk.VkInstance}()
physicalDevice = vk.VK_NULL_HANDLE
logicalDevice = Ref{vk.VkDevice}()
graphicsQueue = Ref{vk.VkQueue}()
surface = vk.VkSurfaceKHR
presentQueue = Ref{vk.VkQueue}()
requiredExtensions = [vk.VK_KHR_SWAPCHAIN_EXTENSION_NAME]
swapChain = Ref{vk.VkSwapchainKHR}()
swapChainImageFormat = vk.VkFormat
swapChainExtent = vk.VkExtent2D
swapChainImages = Vector{vk.VkImage}()
swapChainImageViews = Vector{vk.VkImageView}()

#################### 1.Create instance ####################
function getAppInfo()
    appInfo = Ref(vk.VkApplicationInfo(
        vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        C_NULL, #pNext
        pointer("Hello Triangle"),
        vk.VK_MAKE_VERSION(1, 0, 0),
        pointer("No Engine"),
        vk.VK_MAKE_VERSION(1, 0, 0),
        vk.VK_API_VERSION_1_0()
    ))
end

strings2pp(names::Vector{String}) = (ptr = Base.cconvert(Ptr{Cstring}, names); GC.@preserve ptr Base.unsafe_convert(Ptr{Cstring}, ptr))

function getCreateInfo(appInfo::Ref{vk.VkApplicationInfo})
    glfwExtensions = GLFW.GetRequiredInstanceExtensions()
    extensionCount = length(glfwExtensions)

    createInfo = Ref(vk.VkInstanceCreateInfo(
        vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        C_NULL, #pNext
        UInt32(0), #flags
        Base.unsafe_convert(Ptr{vk.VkApplicationInfo}, appInfo),
        0, #layerCount
        C_NULL, #layerNames
        extensionCount,
        strings2pp(glfwExtensions)
    ))
    createInfo
end

function createInstance()
    appInfo = getAppInfo()
    createInfo = getCreateInfo(appInfo)
    err = vk.vkCreateInstance(createInfo, C_NULL, instance)
    println(err)
    err
end

#################### 2.Using validation layers ####################
#################### 3.Pick Physical device ####################
function checkDeviceExtensionSupport(device)
    extensionCount = Ref{UInt32}(0)
    vk.vkEnumerateDeviceExtensionProperties(device, C_NULL, extensionCount, C_NULL)

    availableExtensions = Vector{vk.VkExtensionProperties}(undef, extensionCount[])
    vk.vkEnumerateDeviceExtensionProperties(device, C_NULL, extensionCount, availableExtensions)

    deviceExtensions = Set(requiredExtensions)
    supportAll = true
    for extension in availableExtensions
        nameChars = UInt8[extension.extensionName...]
        extensionName = String(Base.getindex(nameChars, 1:Base.findfirst(x->x==0, nameChars) - 1))
        delete!(deviceExtensions, extensionName)
        #delete!(deviceExtensions, String(filter(x->x!=0, UInt8[extension.extensionName...])))
    end
    return length(deviceExtensions) == 0
end

function isDeviceSuitable(device::vk.VkPhysicalDevice)
    deviceProperties = Ref{vk.VkPhysicalDeviceProperties}()
    deviceFeatures = Ref{vk.VkPhysicalDeviceFeatures}()
    vk.vkGetPhysicalDeviceProperties(device, deviceProperties)
    vk.vkGetPhysicalDeviceFeatures(device, deviceFeatures)
    if (deviceFeatures[].geometryShader
        #&&deviceProperties[].deviceType == vk.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU
        ) == vk.VK_FALSE
        return false
    end

    extensionsSupported = checkDeviceExtensionSupport(device)
    if !extensionsSupported
        println("does not support required extensions!")
        return false
    end

    swapChainAdequate = false
    swapChainSupport = querySwapChainSupport(device)
    swapChainAdequate = length(swapChainSupport.formats) > 0 && length(swapChainSupport.presentModes) > 0
    if !swapChainAdequate
        println("swap chain is not adequate!")
        return false
    end

    indices = findQueueFamilies(device)
    if !QueueFamilyIndices_isComplete(indices)
        println("queue family indices is not complete!")
        return false
    end
    true
end

function pickPhysicalDevice()
    deviceCount = Ref{Cuint}(0)
    vk.vkEnumeratePhysicalDevices(instance[], deviceCount, C_NULL)
    if (deviceCount == 0)
        println("failed to find GPUs with Vulkan support!")
    end

    devices = Vector{vk.VkPhysicalDevice}(undef, deviceCount[])
    vk.vkEnumeratePhysicalDevices(instance[], deviceCount, devices)

    for device in devices
        if (isDeviceSuitable(device))
            global physicalDevice = device
            break
        end
    end
    if (physicalDevice == vk.VK_NULL_HANDLE)
        println("failed to find a suitable GPU!")
    end
end

#################### 4.Queue families ####################
mutable struct QueueFamilyIndices
    graphicsFamily::Int32
    presentFamily::Int32

    QueueFamilyIndices() = new(-1, -1)
end

function QueueFamilyIndices_isComplete(this)
    this.graphicsFamily != -1 && this.presentFamily != -1
end

function findQueueFamilies(device::vk.VkPhysicalDevice)
    queueFamilyCount = Ref{Cuint}(0)
    vk.vkGetPhysicalDeviceQueueFamilyProperties(device, queueFamilyCount, C_NULL)
    
    queueFamilies = Vector{vk.VkQueueFamilyProperties}(undef, queueFamilyCount[])
    vk.vkGetPhysicalDeviceQueueFamilyProperties(device, queueFamilyCount, queueFamilies)
    
    
    indices = QueueFamilyIndices()
    i = 0 #queueFamilyIndex should start from 0
    for queueFamily in queueFamilies
        if (queueFamily.queueCount > 0)
            if(queueFamily.queueFlags & vk.VK_QUEUE_GRAPHICS_BIT == 1)
                indices.graphicsFamily = i
            end
            
            presentSupport = Ref{vk.VkBool32}(false)
            vk.vkGetPhysicalDeviceSurfaceSupportKHR(device, i, surface, presentSupport)
            if(presentSupport[] == vk.VK_TRUE)
                indices.presentFamily = i
            end
        end

        if (QueueFamilyIndices_isComplete(indices))
            break
        end
        i += 1
    end
    indices
end

#################### 5.Create logical device ####################
function createLogicalDevice()
    indices = findQueueFamilies(physicalDevice)

    queueCreateInfos = Vector{vk.VkDeviceQueueCreateInfo}(undef, 0)
    uniqueQueueFamilies = Set([indices.graphicsFamily, indices.presentFamily])

    for queueFamily in uniqueQueueFamilies
        queuePriority = Ref{Float32}(1.0)
        queueCreateInfo = vk.VkDeviceQueueCreateInfo(
            vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            C_NULL,
            0, #flag
            queueFamily, #queueFamilyIndex
            1, #queueCount
            Base.unsafe_convert(Ptr{Float32}, queuePriority)
        )
        push!(queueCreateInfos, queueCreateInfo)
    end

    deviceFeatures = Ref{vk.VkPhysicalDeviceFeatures}()
    vk.vkGetPhysicalDeviceFeatures(physicalDevice, deviceFeatures)

    flags = vk.VK_DEBUG_REPORT_ERROR_BIT_EXT |
    vk.VK_DEBUG_REPORT_WARNING_BIT_EXT |
    vk.VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT

    createInfo = Ref(vk.VkDeviceCreateInfo(
        vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        C_NULL,
        #0, #flags
        flags,
        length(queueCreateInfos), #createInfoCount
        pointer(queueCreateInfos),
        0, #enabledLayerCount, VilidationLayers is disabled
        C_NULL, #ppEnabledlayerNames
        length(requiredExtensions), #enabledExtensionCount
        strings2pp(requiredExtensions), #ppEnabledExtensionNames
        Base.unsafe_convert(Ptr{vk.VkPhysicalDeviceFeatures}, deviceFeatures)
    ))
    println("ready")
    
    err = vk.vkCreateDevice(physicalDevice, createInfo, C_NULL, logicalDevice)
    if err != vk.VK_SUCCESS
        println(err)
        println("failed to create logical device!")
    end

    vk.vkGetDeviceQueue(logicalDevice[], indices.graphicsFamily, 0, graphicsQueue)
    vk.vkGetDeviceQueue(logicalDevice[], indices.presentFamily, 0, presentQueue)
end

#################### 6.Create window surface ####################
function createSurface()
    global surface = GLFW.CreateWindowSurface(instance[], window)
end

#################### 7.Swap chain ####################
mutable struct SwapChainSupportDetails
    capabilities::Ref{vk.VkSurfaceCapabilitiesKHR}
    formats::Vector{vk.VkSurfaceFormatKHR}
    presentModes::Vector{vk.VkPresentModeKHR}

    SwapChainSupportDetails() = new(Ref{vk.VkSurfaceCapabilitiesKHR}(),
                                    Vector{vk.VkSurfaceFormatKHR}(undef, 1),
                                    Vector{vk.VkPresentModeKHR}(undef, 1))
end

function querySwapChainSupport(device::vk.VkPhysicalDevice)
    details = SwapChainSupportDetails()
    vk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, details.capabilities)
    formatCount = Ref{UInt32}()
    vk.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, formatCount, C_NULL)
    if (formatCount != 0)
        resize!(details.formats, formatCount[])
        vk.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, formatCount, details.formats)
    end

    presentModeCount = Ref{UInt32}()
    vk.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, presentModeCount, C_NULL)
    if (presentModeCount != 0)
        resize!(details.presentModes, presentModeCount[])
        vk.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, presentModeCount, details.presentModes)
    end
    return details
end

function chooseSwapSurfaceFormat(availableFormats::Vector{vk.VkSurfaceFormatKHR})
    if (length(availableFormats) == 1 && availableFormats[0].format == vk.VK_FORMAT_UNDEFINED)
        return [vk.VK_FORMAT_B8G8R8A8_UNORM, vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR]
    end

    for availableFormat in availableFormats
        if (availableFormat.format == vk.VK_FORMAT_B8G8R8A8_UNORM && availableFormat.colorSpace == vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
            return availableFormat
        end
    end
    return availableFormats[0]
end

function chooseSwapPresentMode(availablePresentModes::Vector{vk.VkPresentModeKHR})
    bestMode = vk.VK_PRESENT_MODE_FIFO_KHR
    for availablePresentMode in availablePresentModes
        if availablePresentMode == vk.VK_PRESENT_MODE_MAILBOX_KHR
            return availablePresentMode
        elseif availablePresentMode == vk.VK_PRESENT_MODE_IMMEDIATE_KHR
            bestMode = availablePresentMode
        end
    end
    return bestMode
end

function chooseSwapExtent(capabilities::vk.VkSurfaceCapabilitiesKHR)
    if capabilities.currentExtent.width != typemax(UInt32)
        return capabilities.currentExtent
    else
        actualExtent = vk.VkExtent2D(WIDTH, HEIGHT)
        actualExtent.width = max(capabilities.minImageExtent.width, min(capabilities.maxImageExtent.width, actualExtent.width))
        actualExtent.height = max(capabilities.minImageExtent.height, min(capabilities.maxImageExtent.height, actualExtent.height))
        return actualExtent
    end
end

function createSwapChain()
    swapChainSupport = querySwapChainSupport(physicalDevice)
    surfaceFormat = chooseSwapSurfaceFormat(swapChainSupport.formats)
    presentMode = chooseSwapPresentMode(swapChainSupport.presentModes)
    global swapChainExtent = chooseSwapExtent(swapChainSupport.capabilities[])

    imageCount = swapChainSupport.capabilities[].minImageCount + 1
    if (swapChainSupport.capabilities[].maxImageCount > 0 && imageCount > swapChainSupport.capabilities[].maxImageCount)
        imageCount = swapChainSupport.capabilities[].maxImageCount
    end
    global swapChainImageFormat = surfaceFormat.format

    indices = findQueueFamilies(physicalDevice)

    imageSharingMode = vk.VK_SHARING_MODE_EXCLUSIVE
    queueFamilyIndexCount = 0 # Optional
    queueFamilyIndices = C_NULL # Optional
    if (indices.graphicsFamily != indices.presentFamily)
        imageSharingMode = vk.VK_SHARING_MODE_CONCURRENT
        queueFamilyIndexCount = 2
        queueFamilyIndices = [indices.graphicsFamily, indices.presentFamily]
    end

    createInfo = Ref(vk.VkSwapchainCreateInfoKHR(
        vk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR, #sType
        C_NULL, #pNext
        vk.VkFlags(0), #flags
        surface, #surface
        imageCount, #minImageCount
        swapChainImageFormat, #imageFormat
        surfaceFormat.colorSpace, #imageColorSpace
        swapChainExtent, #imageExtent
        1, #imageArrayLayers
        vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT, #imageUsage
        imageSharingMode, #imageSharingMode::VkSharingMode
        queueFamilyIndexCount, #queueFamilyIndexCount::UInt32
        queueFamilyIndices, #pQueueFamilyIndices::Ptr{UInt32}
        swapChainSupport.capabilities[].currentTransform, #preTransform::VkSurfaceTransformFlagBitsKHR
        vk.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR, #compositeAlpha::VkCompositeAlphaFlagBitsKHR
        presentMode, #presentMode::VkPresentModeKHR
        vk.VK_TRUE, #clipped::VkBool32
        vk.VK_NULL_HANDLE #oldSwapchain::VkSwapchainKHR
    ))

    if (vk.vkCreateSwapchainKHR(logicalDevice[], createInfo, C_NULL, swapChain) != vk.VK_SUCCESS)
        println("failed to create swap chain!")
    end

    imageCount = Ref{UInt32}()
    vk.vkGetSwapchainImagesKHR(logicalDevice[], swapChain[], imageCount, C_NULL)
    resize!(swapChainImages, imageCount[])
    vk.vkGetSwapchainImagesKHR(logicalDevice[], swapChain[], imageCount, swapChainImages)
end

#################### 7.Image view ####################
function createImageViews()
    for image in swapChainImages
        components = vk.VkComponentMapping(
            vk.VK_COMPONENT_SWIZZLE_IDENTITY, #r::VkComponentSwizzle
            vk.VK_COMPONENT_SWIZZLE_IDENTITY, #g::VkComponentSwizzle
            vk.VK_COMPONENT_SWIZZLE_IDENTITY, #b::VkComponentSwizzle
            vk.VK_COMPONENT_SWIZZLE_IDENTITY #a::VkComponentSwizzle
        )
        subresourceRange = vk.VkImageSubresourceRange(
            vk.VK_IMAGE_ASPECT_COLOR_BIT, #aspectMask::VkImageAspectFlags
            0, #baseMipLevel::UInt32
            1, #levelCount::UInt32
            0, #baseArrayLayer::UInt32
            1, #layerCount::UInt32
        )
        createInfo = Ref(vk.VkImageViewCreateInfo(
            vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, #sType::VkStructureType
            C_NULL, #pNext::Ptr{Cvoid}
            0, #flags::VkImageViewCreateFlags
            image, #image::VkImage
            vk.VK_IMAGE_VIEW_TYPE_2D, #viewType::VkImageViewType
            swapChainImageFormat, #format::VkFormat
            components, #components::VkComponentMapping
            subresourceRange, #subresourceRange::VkImageSubresourceRange
        ))
        newImageView = Ref{vk.VkImageView}()
        if (vk.vkCreateImageView(logicalDevice[], createInfo, C_NULL, newImageView) != vk.VK_SUCCESS)
            println("failed to create image views!")
        end
        push!(swapChainImageViews, newImageView[])
    end
end


function vkDestoryInstanceCallback()
    println("callback")
end



function render()
    #println("in render")
end

#################### 0.Setup ####################
function initVulkan()
    if (createInstance() != vk.VK_SUCCESS)
        println("failed to create instance!")
        exit(-1)
    end

    createSurface()
    pickPhysicalDevice()
    createLogicalDevice()
    createSwapChain()
    createImageViews()
end

function initWindow()
    GLFW.Init()
    GLFW.WindowHint(GLFW.CLIENT_API, GLFW.NO_API)
    GLFW.WindowHint(GLFW.RESIZABLE, false)
    # Create a window and its OpenGL context
    global window = GLFW.CreateWindow(WIDTH, HEIGHT, "Vulkan")
end

function mainLoop()
    # Loop until the user closes the window
    while !GLFW.WindowShouldClose(window)
        # Render here
        render()
        # Poll for and process events
        GLFW.PollEvents()
    end
end

function cleanup()
    for imageView in swapChainImageViews
        vk.vkDestroyImageView(logicalDevice[], imageView, C_NULL)
    end
    vk.vkDestroySwapchainKHR(logicalDevice[], swapChain[], C_NULL)
    vk.vkDestroyDevice(logicalDevice[], C_NULL)
    vk.vkDestroySurfaceKHR(instance[], surface, C_NULL)
    vk.vkDestroyInstance(instance[], C_NULL)
    GLFW.DestroyWindow(window)
    GLFW.Terminate()
end

initWindow()
initVulkan()
mainLoop()
cleanup()