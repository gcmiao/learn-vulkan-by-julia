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

    indices = findQueueFamilies(device)
    if !QueueFamilyIndices_isComplete(indices)
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
        0, #enabledExtensionCount
        C_NULL, #ppEnabledExtensionNames
        Base.unsafe_convert(Ptr{vk.VkPhysicalDeviceFeatures}, deviceFeatures)
    ))
    println("ready")
    
    err = vk.vkCreateDevice(physicalDevice, createInfo, C_NULL, logicalDevice)
    if err != vk.VK_SUCCESS
        println(err)
        println("failed to create logical device!")
    end

    vk.vkGetDeviceQueue(logicalDevice[], indices.presentFamily, 0, graphicsQueue)
end

#################### 6.Create window surface ####################
function createSurface()
    global surface = GLFW.CreateWindowSurface(instance[], window)
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